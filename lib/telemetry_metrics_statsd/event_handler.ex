defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{Formatter, Packet, UDP}

  @spec attach(
          [Metrics.t()],
          reporter :: pid(),
          pool_id :: :ets.tid(),
          mtu :: non_neg_integer(),
          prefix :: String.t() | nil,
          formatter :: Formatter.t(),
          global_tags :: Keyword.t()
        ) :: [
          :telemetry.handler_id()
        ]
  def attach(metrics, reporter, pool_id, mtu, prefix, formatter, global_tags) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name, reporter)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          reporter: reporter,
          pool_id: pool_id,
          metrics: metrics,
          mtu: mtu,
          prefix: prefix,
          formatter: formatter,
          global_tags: global_tags
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
        pool_id: pool_id,
        metrics: metrics,
        mtu: mtu,
        prefix: prefix,
        formatter: formatter_mod,
        global_tags: global_tags
      }) do
    packets =
      for metric <- metrics do
        if value = keep?(metric, metadata) && fetch_measurement(metric, measurements, metadata) do
          # The order of tags needs to be preserved so that the final metric name is built correctly.
          tag_values =
            global_tags
            |> Map.new()
            |> Map.merge(metric.tag_values.(metadata))

          tags = Enum.map(metric.tags, &{&1, Map.get(tag_values, &1, "")})
          Formatter.format(formatter_mod, metric, prefix, value, tags)
        else
          :nopublish
        end
      end
      |> Enum.filter(fn l -> l != :nopublish end)

    case packets do
      [] ->
        :ok

      packets ->
        publish_metrics(reporter, pool_id, Packet.build_packets(packets, mtu, "\n"))
    end
  end

  @spec handler_id(:telemetry.event_name(), reporter :: pid) :: :telemetry.handler_id()
  defp handler_id(event_name, reporter) do
    {__MODULE__, reporter, event_name}
  end

  @spec keep?(Metrics.t(), :telemetry.event_metadata()) :: boolean()
  defp keep?(%{keep: nil}, _metadata), do: true
  defp keep?(%{keep: keep}, metadata), do: keep.(metadata)

  @spec fetch_measurement(
          Metrics.t(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata()
        ) :: number() | nil
  defp fetch_measurement(%Metrics.Counter{} = metric, _measurements, _metadata) do
    # For counter, we can ignore the measurements and just use 0.
    case sample(metric) do
      nil -> nil
      _ -> 0
    end
  end

  defp fetch_measurement(metric, measurements, metadata) do
    value =
      case sample(metric) do
        nil ->
          nil

        fun when is_function(fun, 1) ->
          fun.(measurements)

        fun when is_function(fun, 2) ->
          fun.(measurements, metadata)

        key ->
          measurements[key]
      end

    if is_number(value) do
      value
    else
      nil
    end
  end

  @spec publish_metrics(pid(), :ets.tid(), [binary()]) :: :ok
  defp publish_metrics(reporter, pool_id, packets) do
    case TelemetryMetricsStatsd.get_udp(pool_id) do
      {:ok, pid} ->
        Enum.reduce_while(packets, :cont, fn packet, :cont ->
          case UDP.send(pid, packet) do
            :ok ->
              {:cont, :cont}

            {:error, reason} ->
              TelemetryMetricsStatsd.udp_error(reporter, pid, reason)
              {:halt, :halt}
          end
        end)

      :error ->
        :ok
    end
  end

  @spec sample(Metrics.t()) :: Metrics.measurement() | nil
  defp sample(metric) do
    rate = Keyword.get(metric.reporter_options, :sampling_rate, 1.0)
    sample(metric, rate)
  end

  defp sample(metric, 1.0), do: metric.measurement
  defp sample(metric, rate), do: sample(metric, rate, :rand.uniform())

  defp sample(metric, rate, random) when rate >= random, do: metric.measurement
  defp sample(_metric, _rate, _random_real), do: nil
end
