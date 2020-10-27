defmodule TelemetryMetricsStatsd.Test.Helpers do
  @moduledoc false

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
end
