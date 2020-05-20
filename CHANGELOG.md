# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0](https://github.com/beam-telemetry/telemetry_metrics_statsd/tree/v0.4.0)

This release is by far the most feature rich version of the reporter. This wouldn't be possible without the amazing contributions we received! 💛

See the documentation for the new version at https://hexdocs.pm/telemetry_metrics_statsd/0.4.0.

### Highlights

The reporter is now compatible with `Telemetry.Metrics` 0.5.0, which means that it respects the `:keep` and `:drop` options set on metrics.
The `:buckets` option on distribution metric is no longer required and it can be safely removed from these metric definitions (the option was redundant for the StatsD reporter since the beginning).

If you are running in a high volume environment, you can now set the sampling rate of each metric via the `:sampling_rate` reporter option.

And last but not least, we have a few enhancements in how Telemetry.Metrics map to metric types in StatsD/DataDog:

- Both formats now support exporting sum metric as a monotonically increasing counter (via `report_as: :counter` reporter option.
- For DataDog, summary is now exported as a [histogram](https://docs.datadoghq.com/developers/metrics/types/?tab=histogram#metric-types), while distribution maps to [DataDog distribution](https://docs.datadoghq.com/developers/metrics/types/?tab=distribution#metric-types) metric.

### Complete list of changes

#### Added

- Allow to specify an IP address as a target StatsD host (#23), by @hkrutzer.
- Accept an atom for the global metric prefix (#29), by @jasondew.
- Add support for sampling rate configurable per-metric (#28), by @samullen.
- Optionally send sum metric updates as StatsD counter updates (#30), by @jredville.
- Respect the `:keep` and `:drop` options on metrics (#34), by @arkgil.

#### Changed

-  Change the default host from `localhost` to `127.0.0.1` in order to skip redundant IP address lookup (#23), by @hkrutzer.

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
