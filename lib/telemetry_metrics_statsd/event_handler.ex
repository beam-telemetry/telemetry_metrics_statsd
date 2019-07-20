defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{Formatter, Packet, UDP}

  @spec attach(
          [Metrics.t()],
          reporter :: pid(),
          mtu :: non_neg_integer(),
          prefix :: String.t() | nil,
          formatter :: Formatter.t(),
          default_tags :: Keyword.t()
        ) :: [
          :telemetry.handler_id()
        ]
  def attach(metrics, reporter, mtu, prefix, formatter, default_tags) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name, reporter)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          reporter: reporter,
          metrics: metrics,
          mtu: mtu,
          prefix: prefix,
          formatter: formatter,
          default_tags: default_tags
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
        formatter: formatter_mod,
        default_tags: default_tags
      }) do
    packets =
      for metric <- metrics do
        case fetch_measurement(metric, measurements) do
          {:ok, value} ->
            # The order of tags needs to be preserved so that the final metric name is built correctly.
            tag_values = metric.tag_values.(metadata)
            event_tags = Enum.map(metric.tags, &{&1, Map.fetch!(tag_values, &1)})
            tags = Keyword.merge(default_tags, event_tags)
            Formatter.format(formatter_mod, metric, prefix, value, tags)

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

    if is_number(value) do
      {:ok, value}
    else
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
end
