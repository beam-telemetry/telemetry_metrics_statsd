defmodule TelemetryMetricsStatsd.CounterError do
  @counter_ref "telemetry_metrics_statsd_counter_error_ref"

  @spec init :: any()
  def init do
    :persistent_term.put(@counter_ref, :counters.new(1, [:write_concurrency]))
  end

  @spec reset :: :ok
  def reset do
    :counters.put(:persistent_term.get(@counter_ref), 1, 0)
  end

  @spec destroy :: any()
  def destroy do
    :persistent_term.erase(@counter_ref)
  end

  @spec increment(integer()) :: :ok
  def increment(incr \\ 1) when is_integer(incr) and incr > 0 do
    :counters.add(:persistent_term.get(@counter_ref), 1, incr)
  end

  @spec decrement(integer()) :: :ok
  def decrement(decr \\ 1) when is_integer(decr) and decr > 0 do
    :counters.sub(:persistent_term.get(@counter_ref), 1, decr)
  end

  @spec get :: any()
  def get do
    :counters.get(:persistent_term.get(@counter_ref), 1)
  end
end
