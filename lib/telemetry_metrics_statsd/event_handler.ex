defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  @spec attach([Telemetry.Metrics.t()], reporter :: pid()) :: :ok
  def attach(metrics, reporter) do
    for metric <- metrics do
      :ok =
        :telemetry.attach(handler_id(metric, reporter), metric.event_name, &handle_event/4, %{
          metric_name: metric.name,
          metadata_fun: metric.metadata,
          reporter: reporter
        })
    end

    :ok
  end

  @spec detach([Telemetry.Metrics.t()], reporter :: pid()) :: :ok
  def detach(metrics, reporter) do
    for metric <- metrics do
      :telemetry.detach(handler_id(metric, reporter))
    end

    :ok
  end

  defp handle_event(_event, measurements, metadata, config) do
    final_metadata = config.metadata_fun.(metadata)
    TelemetryMetricsStatsd.report(config.reporter, config.metric_name, measurements, final_metadata)
  end

  @spec handler_id(Telemetry.Metrics.t(), reporter :: pid) :: :telemetry.handler_id()
  defp handler_id(metric, reporter) do
    {__MODULE__, reporter, metric.__struct__, metric.name, metric.event_name}
  end
end
