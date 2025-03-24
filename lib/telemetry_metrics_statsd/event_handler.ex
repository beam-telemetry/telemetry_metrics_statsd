defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.Formatter

  @spec attach(
          GenServer.name(),
          [Metrics.t()],
          emitter_module :: module(),
          prefix :: String.t() | nil,
          formatter :: Formatter.t(),
          global_tags :: Keyword.t()
        ) :: [
          :telemetry.handler_id()
        ]
  def attach(registered_name, metrics, emitter_module, prefix, formatter, global_tags) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(registered_name, event_name, emitter_module)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          emitter_module: emitter_module,
          formatter: formatter,
          global_tags: global_tags,
          metrics: metrics,
          name: registered_name,
          prefix: prefix
        })

      handler_id
    end
  end

  @spec detach([:telemetry.handler_id()]) :: :ok
  def detach(handler_ids) do
    Enum.each(handler_ids, &:telemetry.detach/1)
  end

  def handle_event(event, measurements, metadata, %{
        emitter_module: emitter_module,
        formatter: formatter_mod,
        global_tags: global_tags,
        metrics: metrics,
        name: name,
        prefix: prefix
      }) do
    metrics =
      for metric <- metrics,
          keep?(metric, metadata),
          value = fetch_measurement(metric, measurements, metadata),
          value != nil do
        # The order of tags needs to be preserved so that the final metric name is built correctly.
        tag_values =
          global_tags
          |> Map.new()
          |> Map.merge(metric.tag_values.(metadata))

        tags = Enum.map(metric.tags, &{&1, Map.get(tag_values, &1, "")})
        Formatter.format(formatter_mod, metric, prefix, value, tags)
      end

    if internal?(event) do
      publish_internal_metrics(emitter_module, name, metrics)
    else
      publish_metrics(emitter_module, name, metrics)
    end
  end

  @spec handler_id(
          registered_name :: GenServer.name(),
          :telemetry.event_name(),
          emitter_module :: module()
        ) :: :telemetry.handler_id()
  defp handler_id(registered_name, event_name, emitter_module) do
    {__MODULE__, registered_name, emitter_module, event_name}
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

  defp internal?([:telemetry_metrics_statsd | _]), do: true
  defp internal?(_), do: false

  @spec publish_metrics(emitter_module :: module(), name :: GenServer.name(), [binary()]) :: :ok
  defp publish_metrics(_emitter_module, _name, []), do: :ok

  defp publish_metrics(emitter_module, name, metrics) do
    Enum.each(metrics, fn metric -> emitter_module.emit(name, metric) end)
  end

  defp publish_internal_metrics(_emitter_module, _name, []), do: :ok

  defp publish_internal_metrics(emitter_module, name, metrics) do
    Enum.each(metrics, fn metric -> emitter_module.emit_internal(name, metric) end)
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
