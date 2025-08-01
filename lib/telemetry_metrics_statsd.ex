defmodule TelemetryMetricsStatsd do
  @moduledoc """
  `Telemetry.Metrics` reporter for StatsD-compatible metric servers.

  To use it, start the reporter with the `start_link/1` function, providing it a list of
  `Telemetry.Metrics` metric definitions:

      import Telemetry.Metrics

      TelemetryMetricsStatsd.start_link(
        metrics: [
          counter("http.request.count"),
          sum("http.request.payload_size"),
          last_value("vm.memory.total")
        ]
      )

  > Note that in the real project the reporter should be started under a supervisor, e.g. the main
  > supervisor of your application.

  By default the reporter sends metrics to 127.0.0.1:8125 - both hostname and port number can be
  configured using the `:host` and `:port` options.

      TelemetryMetricsStatsd.start_link(
        metrics: metrics,
        host: "statsd",
        port: 1234
      )

  Alternatively, a Unix domain socket path can be provided using the `:socket_path` option.

      TelemetryMetricsStatsd.start_link(
        metrics: metrics,
        socket_path: "/var/run/statsd.sock"
      )

  If the `:socket_path` option is provided, `:host` and `:port` parameters are ignored and the
  connection is established exclusively via Unix domain socket.

  Note that the reporter doesn't aggregate metrics in-process - it sends metric updates to StatsD
  whenever a relevant Telemetry event is emitted.

  By default, the reporter sends metrics through a single socket. To reduce contention when there are
  many metrics to be sent, more sockets can be configured to be opened through the `pool_size` option.

      TelemetryMetricsStatsd.start_link(
        metrics: metrics,
        pool_size: 10
      )

  When the `pool_size` is bigger than 1, the sockets are randomly selected out of the pool each time
  they need to be used

  ## Translation between Telemetry.Metrics and StatsD

  In this section we walk through how the Telemetry.Metrics metric definitions are mapped to StatsD
  metrics and their types at runtime.

  Telemetry.Metrics metric names are translated as follows:
    * if the metric name was provided as a string, e.g. `"http.request.count"`, it is sent to
      StatsD server as-is
    * if the metric name was provided as a list of atoms, e.g. `[:http, :request, :count]`, it is
      first converted to a string by joining the segments with dots. In this example, the StatsD
      metric name would be `"http.request.count"` as well

  Since there are multiple implementations of StatsD and each of them provides slightly different
  set of features, other aspects of metric translation are controlled by the formatters.
  The formatter can be selected using the `:formatter` option. Currently only two formats are
  supported - `:standard` and `:datadog`.

  The following table shows how `Telemetry.Metrics` metrics map to standard StatsD metrics:

  | Telemetry.Metrics | StatsD |
  |-------------------|--------|
  | `last_value`      | `gauge` |
  | `counter`         | `counter` |
  | `sum`             | `gauge` or `counter` |
  | `summary`         | `timer` |
  | `distribution`    | `timer` |

  [DataDog](https://docs.datadoghq.com/developers/metrics/types/?tab=count#metric-types) provides a richer
  set of metric types:

  | Telemetry.Metrics | DogStatsD |
  |-------------------|-----------|
  | `last_value`      | `gauge` |
  | `counter`         | `counter` |
  | `sum`             | `gauge` or `counter` |
  | `summary`         | `histogram`  |
  | `distribution`    | `distribution` |

  ### The standard StatsD formatter

  The `:standard` formatter is compatible with the
  [Etsy implementation](https://github.com/statsd/statsd/blob/master/docs/metric_types.md) of StatsD.
  Since this particular implementation doesn't support explicit tags, tag values are appended as
  consecutive segments of the metric name. For example, given the definition

      counter("db.query.count", tags: [:table, :operation])

  and the event

      :telemetry.execute([:db, :query], %{}, %{table: "users", operation: "select"})

  the StatsD metric name would be `"db.query.count.users.select"`. Note that the tag values are
  appended to the base metric name in the order they were declared in the metric definition.

  Another important aspect of the standard formatter is that all measurements are converted to
  integers, i.e. no floats are ever sent to the StatsD daemon.

  Now to the metric types!

  #### Counter

  Telemetry.Metrics counter is simply represented as a StatsD counter. Each event the metric is
  based on increments the counter by 1. To be more concrete, given the metric definition

      counter("http.request.count")

  and the event

      :telemetry.execute([:http, :request], %{duration: 120})

  the following line would be send to StatsD

      "http.request.count:1|c"

  Note that the counter was bumped by 1, regardless of the measurements included in the event
  (careful reader will notice that the `:count` measurement we chose for the metric wasn't present
  in the map of measurements at all!). Such behaviour conforms to the specification of counter as
  defined by `Telemetry.Metrics` package - a counter should be incremented by 1 every time a given
  event is dispatched.

  #### Last value

  Last value metric is represented as a StatsD gauge, whose values are always set to the value
  of the measurement from the most recent event. With the following metric definition

      last_value("vm.memory.total")

  and the event

      :telemetry.execute([:vm, :memory], %{total: 1024})

  the following metric update would be send to StatsD

      "vm.memory.total:1024|g"

  #### Sum

  Sum metric is also represented as a gauge - the difference is that it always changes relatively
  and is never set to an absolute value. Given metric definition below

      sum("http.request.payload_size")

  and the event

      :telemetry.execute([:http, :request], %{payload_size: 1076})

  the following line would be send to StatsD

      "http.request.count:+1076|g"

  When the measurement is negative, the StatsD gauge is decreased accordingly.

  When the `report_as: :counter` reporter option is passed, the sum metric is reported as
  a counter and increased with the value provided. Only positive values are allowed, negative
  measurements are discarded and logged.

  Given the metric definition

      sum("kafka.consume.batch_size", reporter_options: [report_as: :counter])

  and the event

      :telemetry.execute([:kafka, :consume], %{batch_size: 200})

  the following would be sent to StatsD

      "kafka.consume.batch_size:200|c"

  #### Summary

  The summary is simply represented as a StatsD timer, since it should generate statistics about
  gathered measurements. Given the metric definition below

      summary("http.request.duration")

  and the event

      :telemetry.execute([:http, :request], %{duration: 120})

  the following line would be send to StatsD

      "http.request.duration:120|ms"

  #### Distribution

  There is no metric in original StatsD implementation equivalent to Telemetry.Metrics distribution.
  However, histograms can be enabled for selected timer metrics in the
  [StatsD daemon configuration](https://github.com/statsd/statsd/blob/master/docs/metric_types.md#timing).
  Because of that, the distribution is also reported as a timer. For example, given the following metric
  definition

      distribution("http.request.duration")

  and the event

      :telemetry.execute([:http, :request], %{duration: 120})

  the following line would be send to StatsD

      "http.request.duration:120|ms"

  ### The DataDog formatter

  The DataDog formatter is compatible with [DogStatsD](https://docs.datadoghq.com/developers/dogstatsd/),
  the DataDog StatsD service bundled with its agent.

  #### Tags

  The main difference from the standard formatter is that DataDog supports explicit tagging in its
  protocol. Using the same example as with the standard formatter, given the following definition

      counter("db.query.count", tags: [:table, :operation])

  and the event

      :telemetry.execute([:db, :query], %{}, %{table: "users", operation: "select"})

  the metric update packet sent to StatsD would be `db.query.count:1|c|#table:users,operation:select`.

  Tag values that cannot be converted to strings (such as maps, tuples, PIDs, ports, or references)
  are safely handled by converting them to the string `"_unprocessable"`.

  #### Metric types

  There is no difference in how the counter and last value metrics are handled between
  the standard and DataDog formatters.

  The sum metric is reporter as DataDog counter, which is being transformed into a rate metric
  in DataDog: https://docs.datadoghq.com/developers/metrics/dogstatsd_metrics_submission/#count.
  To be able to observe the actual sum of measurements make sure to use the
  [`as_count()`](https://docs.datadoghq.com/developers/metrics/type_modifiers/?tab=rate#in-application-modifiers)
  modifier in your DataDog dashboard. The `report_as: :count` option does not have any effect
  with the DataDog formatter.

  The summary metric is reported as [DataDog
  histogram](https://docs.datadoghq.com/developers/metrics/types/?tab=histogram), as that is the
  metric that provides a set of statistics about gathered measurements on the DataDog side.

  The distribution is flushed as [DataDog
  distribution](https://docs.datadoghq.com/developers/metrics/types/?tab=distribution) metric, which
  provides statistically correct aggregations of data gathered from multiple services or DogStatsD
  agents.

  Also note that DataDog allows measurements to be floats, that's why no rounding is performed when
  formatting the metric.

  ## Global tags

  The library provides an option to specify a set of global tag values, which are available to all
  metrics running under the reporter.

  For example, if you're running your application in multiple deployment environment (staging, production,
  etc.), you might set the environment as a global tag:

      TelemetryMetricsStatsd.start_link(
        metrics: [
          counter("http.request.count", tags: [:env])
          ],
          global_tags: [env: "prod"]
      )

  Note that if the global tag is to be sent with the metric, the metric needs to have it listed under the
  `:tags` option, just like any other tag.

  Also, if the same key is configured as a global tag and emitted as a part of event metadata or returned
  by the `:tag_values` function, the metadata/`:tag_values` take precedence and override the global tag
  value.

  ## Prefixing metric names

  Sometimes it's convenient to prefix all metric names with particular value, to group them by the
  name of the service, the host, or something else. You can use `:prefix` option to provide a prefix
  which will be prepended to all metrics published by the reporter (regardless of the formatter used).

  ## Maximum datagram size

  This section is only relevant for metrics sent over UDP, which is the default. The following is
  not relevant if you're using the Unix Domain Socket emitter.

  When metrics are sent to StatsD over UDP, it's important that the size of the datagram does not
  exceed the Maximum Transmission Unit (MTU), of the link, so that no data is lost on the way.
  By default the reporter will break up the datagrams at 512 bytes, but this is configurable via
  the `:mtu` option. Properly setting the MTU will have a drastic impact on performance. To set this field,
  look at your network's MTU, then subtract a UDP packet's overhead (at least 28 bytes for IPv4 and 48 bytes
  for IPv6).

  ## Sampling data

  It's not always convenient to capture every piece of data, such as in the case of high-traffic
  applications. In those cases, you may want to capture a "sample" of the data. You can do this
  by passing `[sampling_rate: <rate>]` as an option to `:reporter_options`, where `rate` is a
  value between 0.0 and 1.0. The default `:sampling_rate` is 1.0, which means that all
  the measurements are being captured.

  ### Example

      TelemetryMetricsStatsd.start_link(
        metrics: [
          counter("http.request.count"),
          summary("http.request.duration", reporter_options: [sampling_rate: 0.1]),
          distribution("http.request.duration", reporter_options: [sampling_rate: 0.1])
        ]
      )

  In this example, we are capturing 100% of the measurements for the counter, but only 10% for both
  summary and distribution.

  ## Overload Protection

  `TelemetryMetricsStatsd` can measure the amount of time metrics spend in the message queues of the processes
  that emit them, and take corrective action if this time is too long. To enable this functionality,
  set the `max_queue_dwell_time` when setting up your reporter

      TelemetryMetricsStatsd.start_link(
        metrics: [
          ...
        ],
       # Take action if a probe message sits in the queue for 1000ms or longer
       max_queue_dwell_time: 1000
      )


  If this key is set, a probe message is sent every second, and if this message takes longer than 100ms
  to work its way through the queue, the emitter begins applying the additive increase multiplicative decrease
  algorithm to reduce the number of metrics emitted by the system. Each time the system fails the dwell time
  check, the number of metrics emitted is reduced by 50%. This happens until only 0.1% of the total metrics are
  being emitted. When the percentage of metrics emitted is reduced, a `critical` Logger message is emitted, as
  are the following metrics:

     *  `"telemetry_metrics_statsd.congestion.emit_percentage.decrease.count"`

     *  `"telemetry_metrics_statsd.congestion.emit_percentage.decrease.value"`

  When the emit percentage is less than 100 and a dwell time probe succeeds, the emit percentage is increased by 1%. When
  this happens, an `info` Logger message is logged, and the following metrics are emitted:

     * `"telemetry_metrics_statsd.congestion.emit_percentage.increase.count"`

     * `"telemetry_metrics_statsd.congestion.emit_percentage.increase.value"`

  ## Complete Configuration

  #{TelemetryMetricsStatsd.Options.docs()}


  ## Performance

  #### Baseline performance characteristics

  The default configuration for `TelemetryMetricsStatsd` with a single emitter can send several hundred of thousand metrics per
  second on a single server. That said, this baseline  can be dramatically improved by configuring the library for the specific needs
  of your application.

  For the UDP emitter, pay attention to the `mtu` and `emitters` keys. In testing, it was found that setting the `mtu` correctly has
  a dramatic impact on performance. The default value for `emitters` is conservative, it can likely be increased, and our testing
  indicated that `5` is a reasonable size for the pool. Increasing it beyond this value was found to negatively impact throughput. You
  are encouraged to experiment and find the values that work for you.

  For the Unix Domain socket emitter, testing indicated that increasing the `emitters` value beyond `2` negatively impacted performance.


  ## Metrics

  The following metrics are emitted by `TelemetryMetricsStatsd`

  * `"telemetry_metrics_statsd.congestion.dwell_time.duration"` - Emitted when a dwell time check completes, emits the value of the dwell
  time, in microseconds.
  * `"telemetry_metrics_statsd.congestion.emit_percentage.decrease.count"` - Fired each time an emitter reduces its emit percentage.
  Count is always one per emitter.
  * `"telemetry_metrics_statsd.congestion.emit_percentage.decrease.value"` - Fired each time an emitter reduces its emit percentage.
  The value is the new percentage.
  * `"telemetry_metrics_statsd.congestion.emit_percentage.increase.count"` - Fired each time an emitter increases its emit percentage.
  Count is always one per emitter.
  * `"telemetry_metrics_statsd.congestion.emit_percentage.increase.value"` - Fired each time an emitter increases its emit percentage.
  The value is the new percentage.


  """

  require Logger
  require Record

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.Emitter
  alias TelemetryMetricsStatsd.EventHandler
  alias TelemetryMetricsStatsd.Options

  @type prefix :: String.t() | atom() | nil
  @type host :: String.t() | :inet.ip_address()
  @type option ::
          {:port, :inet.port_number()}
          | {:host, host()}
          | {:socket_path, Path.t()}
          | {:metrics, [Metrics.t()]}
          | {:mtu, non_neg_integer()}
          | {:prefix, prefix()}
          | {:formatter, :standard | :datadog}
          | {:global_tags, Keyword.t()}
          | {:host_resolution_interval, non_neg_integer()}
  @type options :: [option]

  @doc """
  Reporter's child spec.

  This function allows you to start the reporter under a supervisor like this:

      children = [
        {TelemetryMetricsStatsd, options}
      ]

  See `start_link/1` for a list of available options.
  """
  @spec child_spec(options) :: Supervisor.child_spec()
  def child_spec(options) do
    name = Keyword.get(options, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [options]}}
  end

  @doc """
  Starts a reporter and links it to the calling process.

  The available options are:
  #{TelemetryMetricsStatsd.Options.docs()}

  You can read more about all the options in the `TelemetryMetricsStatsd` module documentation.

  ## Example

      import Telemetry.Metrics

      TelemetryMetricsStatsd.start_link(
        metrics: [
          counter("http.request.count"),
          sum("http.request.payload_size"),
          last_value("vm.memory.total")
        ],
        prefix: "my-service"
      )
  """
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options) do
    case Options.validate(options) do
      {:ok, %Options{} = options} ->
        emitter_module =
          case options.host do
            {:local, _path} ->
              Emitter.Domain

            _ ->
              Emitter.UDP
          end

        children = [
          {PartitionSupervisor,
           [
             child_spec: emitter_module.child_spec(options),
             name: emitter_module.supervisor_name(options.name),
             partitions: options.emitters
           ]},
          {EventHandler, [options, emitter_module]}
        ]

        Supervisor.start_link(children, strategy: :one_for_all)

      {:error, _} = err ->
        err
    end
  end
end
