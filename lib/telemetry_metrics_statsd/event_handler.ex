defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{Packet, UDP}

  @spec attach(
          [Metrics.t()],
          reporter :: pid(),
          mtu :: non_neg_integer(),
          prefix :: String.t() | nil,
          formatter :: module()
        ) :: [
          :telemetry.handler_id()
        ]
  def attach(metrics, reporter, mtu, prefix, formatter) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name, reporter)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          reporter: reporter,
          metrics: metrics,
          mtu: mtu,
          prefix: prefix,
          formatter: formatter
        })

      handler_id
    end
  end

  @spec detach([:telemetry.handler_id()]) :: :ok
  def detach(handler_ids) do
    for handler_id <- handler_ids do
      :telemetry.detach(handler_id)
    end

    :ok
  end

  def handle_event(_event, measurements, metadata, %{
        reporter: reporter,
        metrics: metrics,
        mtu: mtu,
        prefix: prefix,
        formatter: formatter_mod
      }) do
    packets =
      for metric <- metrics do
        case fetch_measurement(metric, measurements) do
          {:ok, value} ->
            # The order of tags needs to be preserved so that the final metric name is built correctly.
            tag_values = metric.tag_values.(metadata)
            tags = Enum.map(metric.tags, &{&1, Map.fetch!(tag_values, &1)})
            normalized_name = add_prefix_to_metric_name(prefix, metric.name)
            formatter_mod.format(metric, normalized_name, value, tags)

          :error ->
            :nopublish
        end
      end
      |> Enum.filter(fn l -> l != :nopublish end)

    case packets do
      [] ->
        :ok

      packets ->
        publish_metrics(reporter, Packet.build_packets(packets, mtu, "\n"))
    end
  end

  @spec handler_id(:telemetry.event_name(), reporter :: pid) :: :telemetry.handler_id()
  defp handler_id(event_name, reporter) do
    {__MODULE__, reporter, event_name}
  end

  @spec fetch_measurement(Metrics.t(), :telemetry.event_measurements()) ::
          {:ok, number()} | :error
  defp fetch_measurement(%Metrics.Counter{}, _measurements) do
    # For counter, we can ignore the measurements and just use 0.
    {:ok, 0}
  end

  defp fetch_measurement(metric, measurements) do
    value =
      case metric.measurement do
        fun when is_function(fun, 1) ->
          fun.(measurements)

        key ->
          measurements[key]
      end

    cond do
      is_float(value) ->
        # The StatsD metrics we implement support only numerical values.
        {:ok, round(value)}

      is_integer(value) ->
        {:ok, value}

      true ->
        :error
    end
  end

  @spec publish_metrics(pid(), [binary()]) :: :ok
  defp publish_metrics(reporter, packets) do
    udp = TelemetryMetricsStatsd.get_udp(reporter)

    Enum.reduce_while(packets, :cont, fn packet, :cont ->
      case UDP.send(udp, packet) do
        :ok ->
          {:cont, :cont}

        {:error, reason} ->
          TelemetryMetricsStatsd.udp_error(reporter, udp, reason)
          {:halt, :halt}
      end
    end)
  end

  defp add_prefix_to_metric_name(nil, metric_name), do: metric_name
  defp add_prefix_to_metric_name(prefix, metric_name), do: [prefix | metric_name]
end
