defmodule TelemetryMetricsStatsd.LogLevel do
  # TODO: remove this when we depend on Elixir 1.11+, where Logger.warning/1
  # was introduced.
  @log_level_warning if macro_exported?(Logger, :warning, 1), do: :warning, else: :warn


  def warning() do
    @log_level_warning
  end

end
