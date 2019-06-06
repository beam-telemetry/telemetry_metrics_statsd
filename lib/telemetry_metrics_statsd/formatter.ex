defmodule TelemetryMetricsStatsd.Formatter do
  @moduledoc false

  @callback format(
              prefix :: String.t() | nil,
              Telemetry.Metrics.t(),
              :telemetry.event_value(),
              tags :: [
                {Telemetry.Metrics.tag(), term()}
              ]
            ) :: binary()
end
