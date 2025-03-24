defmodule TelemetryMetricsStatsd.Test.Helpers do
  @moduledoc false

  alias TelemetryMetricsStatsd.Options

  def new_emitter(emitter_module, defaults, overrides) do
    {supervised?, overrides} = Keyword.pop(overrides, :supervised?, true)

    {:ok, options} =
      defaults
      |> Keyword.merge(overrides)
      |> Options.validate()

    if supervised? do
      ExUnit.Callbacks.start_supervised({emitter_module, options})
    else
      emitter_module.start_link(options)
    end
  end

  def emit(emitter, data) do
    GenServer.call(emitter, {:emit, data})
  end

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
