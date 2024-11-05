defmodule TelemetryMetricsStatsd.Test.Helpers do
  @moduledoc false

  use ExUnit.Case

  def given_counter(event_name, opts \\ []) do
    Telemetry.Metrics.counter(event_name, opts)
  end

  def given_sum(event_name, opts \\ []) do
    Telemetry.Metrics.sum(event_name, opts)
  end

  def given_last_value(event_name, opts \\ []) do
    Telemetry.Metrics.last_value(event_name, opts)
  end

  def given_summary(event_name, opts \\ []) do
    Telemetry.Metrics.summary(event_name, opts)
  end

  def given_distribution(event_name, opts \\ []) do
    Telemetry.Metrics.distribution(event_name, opts)
  end

  def setup_telemetry(events, config \\ []) do
    telemetry_handle_id = "test-telemetry-handler-#{inspect(self())}"

    :ok =
      :telemetry.attach_many(
        telemetry_handle_id,
        events,
        &send_to_pid/4,
        config
      )

    :ok = on_exit(fn -> :telemetry.detach(telemetry_handle_id) end)
  end

  defp send_to_pid(event, measurements, metadata, config) do
    pid = config[:pid] || self()

    send(pid, {:telemetry_event, {event, measurements, metadata, config}})
  end
end
