defmodule TelemetryMetricsStatsd.Emitter do
  @moduledoc false
  @callback emit(name :: GenServer.name(), metric :: iodata()) :: :ok
  @callback emit_internal(name :: GenServer.name(), metric :: iodata()) :: :ok
end
