# TelemetryMetricsStatsd

[![CircleCI](https://circleci.com/gh/arkgil/telemetry_metrics_statsd.svg?style=svg)](https://circleci.com/gh/arkgil/telemetry_metrics_statsd)

`Telemetry.Metrics` reporter for StatsD-compatible metric servers.

To use it, start the reporter with the `start_link/1` function, providing it a list of
`Telemetry.Metrics` metric definitions:

```elixir
import Telemetry.Metrics

TelemetryMetricsStatsd.start_link(
  metrics: [
    counter("http.request.count"),
    sum("http.request.payload_size"),
    last_value("vm.memory.total")
  ]
)
```

or put it under a supervisor:

```elixir
import Telemetry.Metrics

children = [
  {TelemetryMetricsStatsd, [
    metrics: [
      counter("http.request.count"),
      sum("http.request.payload_size"),
      last_value("vm.memory.total")
    ]
  ]}
]

Supervisor.start_link(children, ...)
```

By default the reporter sends metrics to localhost:8125 - both hostname and port number can be
configured using the `:host` and `:port` options. You can also configure the prefix for all the
published metrics using the `:prefix` option.

Note that the reporter doesn't aggregate metrics in-process - it sends metric updates to StatsD
whenever a relevant Telemetry event is emitted.