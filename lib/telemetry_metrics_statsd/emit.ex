defmodule TelemetryMetricsStatsd.Emit do

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.Formatter
  alias TelemetryMetricsStatsd.Packet
  alias TelemetryMetricsStatsd.UDP

  def emit(udp, reporter, measurements, metadata, metrics, options) do
    packets =
      for metric <- metrics do
        if value = keep?(metric, metadata) && fetch_measurement(metric, measurements, metadata) do
          # The order of tags needs to be preserved so that the final metric name is built correctly.
          tag_values =
            options.global_tags
            |> Map.new()
            |> Map.merge(metric.tag_values.(metadata))

          tags = Enum.map(metric.tags, &{&1, Map.get(tag_values, &1, "")})
          Formatter.format(options.formatter, metric, options.prefix, value, tags)
        else
          :nopublish
        end
      end
      |> Enum.filter(fn l -> l != :nopublish end)

    case packets do
      [] ->
        :ok

      packets ->
        publish_metrics(udp, reporter, Packet.build_packets(packets, options.mtu, "\n"))
    end
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

  @spec publish_metrics(UDP.t(), pid(), [binary()]) :: :ok
  defp publish_metrics(udp, reporter, packets) do
    Enum.reduce_while(packets, :cont, fn packet, :cont ->
      case UDP.send(udp, packet) do
        :ok ->
          {:cont, :cont}

        {:error, reason} ->
          udp_error(reporter, udp, reason)
          {:halt, :halt}
      end
    end)
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

  @doc false
  @spec udp_error(pid(), UDP.t(), reason :: term) :: :ok
  defp udp_error(reporter, udp, reason) do
    GenServer.cast(reporter, {:udp_error, udp, reason})
  end
end
