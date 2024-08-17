# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.7.1)

#### Added

- Support `TelemetryMetrics` version 1.0. (#96)
- Log the binary size when the message exceeds the configured MTU. (#95)

#### Fixed

- Fix the reporter crash when the host resolution fails. (#96)

## [0.7.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.7.0)

The major addition in this release is support for IPv6 StatsD hosts.

#### Added

- Support sending metrics to IPv6 hosts. (#79) @cheerfulstoic
- Support OTP 26 and 25 and Elixir 1.14 and 1.15. (#83) @mopp

#### Fixed

- Remove deprecation warnings for `Logger.warn`. (#80) @whatyouhide
- Don't emit metrics with empty string tag when standard formatter is used. (#86)

## [0.6.3](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.6.3)

#### Added

- Allow usage of the library with NimbleOptions ~> 1.0. (#74)

## [0.6.2](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.6.2)

#### Fixed

- Fix deprecation warning coming from NimbleOptions. (#69)

## [0.6.1](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.6.1)

This release adds support for telemetry 1.0.

## [0.6.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.6.0)

This release comes with performance improvements and better defaults for hostname resolution.

Changes to hostname resolution are a _potentially breaking change_. Specifically, previouslyby default the reporter would send the packet using the hostname as a target, which means the hostname would be resolved using the default DNS stack of the runtime on every send, which is expensive. Now the reporter resolves the hostname once on startup and sends the metrics to the resolved IP. If the IP address of your target host is not static, configure the `:host_resolution_interval` accordingly when updating to this version.

#### Changed

- Increase the default pool size to 10. (#56)
- Resolve the target hostname to IP address when the reporter starts. (#52)

#### Fixed

- Gracefully handle the situation where the pool is empty due repeated errors on send. (#54)

## [0.5.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.5.0)

This release brings a few new features, performance improvements, but also one backwards-incompatible change.

Again, all credit for the improvements goes to our fantastic contributors!

### Complete list of changes

This version is compatible with Telemetry.Metrics v0.6.0, meaning that you can use 2-arity measurement functions, accepting both event measurements and metadata.

It's also tested for compatibility with Elixir 1.11.

Among various improvements, this release also brings one backwards-incompatible change in DataDog formatter, which fixes the previous, incorrect behaviour.
Previously, the sum metric updates would be translated to gauge increments/decrements on the DataDog side.
However, DataDog doesn't support relative changes of gauge's value, and so the reported metric would show only the last measurement sent by the reporter.
The current version correctly sends sum updates as relative changes to the DataDog counter, which results in correct metric values on the DataDog side.

#### Added

- Send metrics to Unix Domain Sockets via `:socket_path` option. (#37 by @kamilkowalski)
- Open multiple sockets to send metrics through via `:pool_size` option. (#41 by @epilgrim)
- Dynamically resolve configured hostname to avoid DNS lookup on every metric update. (#48 by @haljin)

#### Changed

- Allow empty and non-existent tag values in published events. (#49)
- Send sum metric updates with DataDog formatter as relative counter changes instead of relative gauge changes. (#47)

#### Fixed

- Prevent port leak by explicitly closing the failing socket. (#40 by @kamilkowalski)

## [0.4.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.4.0)

This release is by far the most feature rich update of the reporter. This wouldn't be possible without the amazing contributions we received! 💛

See the documentation for the new version at https://hexdocs.pm/telemetry_metrics_statsd/0.4.0.

### Highlights

The reporter is now compatible with Telemetry.Metrics 0.5.0, which means that it respects the `:keep` and `:drop` options set on metrics.
The `:buckets` option on distribution metrics is no longer required and it can be safely removed from these metric definitions (the option was redundant for the StatsD reporter since the beginning).

If you are running reporter in a high volume environment, you can now set the sampling rate of each metric via the `:sampling_rate` reporter option, to limit the number of metric updates sent to the StatsD daemon.

And last but not least, we have a few enhancements in how Telemetry.Metrics map to metric types in StatsD/DataDog:

- Both formats now support exporting sum metric as a monotonically increasing counter (via `report_as: :counter` reporter option).
- For DataDog, summary is now exported as a [histogram](https://docs.datadoghq.com/developers/metrics/types/?tab=histogram#metric-types), while distribution maps to [DataDog distribution](https://docs.datadoghq.com/developers/metrics/types/?tab=distribution#metric-types) metric.

### Complete list of changes

#### Added

- Allow to specify an IP address as a target StatsD host (#23), by @hkrutzer.
- Accept an atom for the global metric prefix (#29), by @jasondew.
- Add support for sampling rate configurable per-metric (#28), by @samullen.
- Optionally send sum metric updates as StatsD counter updates (#30), by @jredville.
- Respect the `:keep` and `:drop` options on metrics (#34), by @arkgil.

#### Changed

- Change the default host from `localhost` to `127.0.0.1` in order to skip redundant IP address lookup (#23), by @hkrutzer.

## [0.3.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.3.0)

### Added

- `:global_tags` options to specify static tag values available for all metrics under the reporter

## [0.2.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.2.0)

This release adds support for Telemetry.Metrics summary metric, as well as integration with DataDog.

### Added

- `Telemetry.Metrics.summary/2` can be now included in a list of metrics tracked by the reporter
- `:formatter` option which determines whether standard or DataDog metric format is used

## [0.1.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.1.0)

First version of the library.
