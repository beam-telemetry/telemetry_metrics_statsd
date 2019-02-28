defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{Formatter, UDP}

  @spec attach([Metrics.t()], reporter :: pid()) :: [:telemetry.handler_id()]
  def attach(metrics, reporter) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name, reporter)

      :ok =
        :telemetry.attach(handler_id, event_name, &handle_event/4, %{
          reporter: reporter,
          metrics: metrics
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

  defp handle_event(_event, measurements, metadata, %{reporter: reporter, metrics: metrics}) do
    payload =
      for metric <- metrics do
        case fetch_measurement(metric, measurements) do
          {:ok, value} ->
            # The order of tags needs to be preserved so that the final metric name is built correctly.
            final_metadata = metric.metadata.(metadata)
            tags = Enum.map(metric.tags, &{&1, Map.fetch!(final_metadata, &1)})
            Formatter.format(metric, value, tags)

          :error ->
            :nopublish
        end
      end
      |> Enum.filter(fn l -> l != :nopublish end)
      # TODO: chunk the packets per MTU size.
      |> Enum.join("\n")

    publish_metrics(reporter, payload)
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
      # The StatsD metrics we implement support only numerical values.
      {:ok, value}
    else
      :error
    end
  end

  @spec publish_metrics(pid(), binary()) :: :ok
  defp publish_metrics(reporter, payload) do
    udp = TelemetryMetricsStatsd.get_udp(reporter)
    case UDP.send(udp, payload) do
      :ok ->
        :ok
      {:error, reason} ->
        TelemetryMetricsStatsd.udp_error(reporter, udp, reason)
    end
  end
end
