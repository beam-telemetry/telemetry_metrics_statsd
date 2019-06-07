defmodule TelemetryMetricsStatsd.Formatter do
  @moduledoc false

  @callback format(
              Telemetry.Metrics.t(),
              Telemetry.Metrics.normalized_metric_name(),
              :telemetry.event_value(),
              tags :: [
                {Telemetry.Metrics.tag(), term()}
              ]
            ) :: binary()
end
