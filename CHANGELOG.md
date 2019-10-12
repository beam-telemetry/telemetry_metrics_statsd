# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
