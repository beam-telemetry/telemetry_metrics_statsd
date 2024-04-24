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

  Metrics are sent to StatsD over UDP, so it's important that the size of the datagram does not
  exceed the Maximum Transmission Unit, or MTU, of the link, so that no data is lost on the way.
  By default the reporter will break up the datagrams at 512 bytes, but this is configurable via
  the `:mtu` option.

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
  """

  use GenServer

  require Logger
  require Record

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{EventHandler, Options, UDP}

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

  Record.defrecordp(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

  # TODO: remove this when we depend on Elixir 1.11+, where Logger.warning/1
  # was introduced.
  @log_level_warning if macro_exported?(Logger, :warning, 1), do: :warning, else: :warn

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
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}}
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
      {:ok, options} ->
        GenServer.start_link(__MODULE__, options)

      {:error, _} = err ->
        err
    end
  end

  @doc false
  @spec get_udp(:ets.tid()) :: {:ok, UDP.t()} | :error
  def get_udp(pool_id) do
    # The table can be empty if the UDP error is reported for all the sockets.
    case :ets.lookup(pool_id, :udp) do
      [] ->
        Logger.error("Failed to publish metrics over UDP: no open sockets available.")
        :error

      udps ->
        {:udp, udp} = Enum.random(udps)
        {:ok, udp}
    end
  end

  @doc false
  @spec get_pool_id(pid()) :: :ets.tid()
  def get_pool_id(reporter) do
    GenServer.call(reporter, :get_pool_id)
  end

  @doc false
  @spec udp_error(pid(), UDP.t(), reason :: term) :: :ok
  def udp_error(reporter, udp, reason) do
    GenServer.cast(reporter, {:udp_error, udp, reason})
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    metrics = Map.fetch!(options, :metrics)

    {initialized_properly, udp_config} =
      case options.host do
        {:local, _} = host -> {true, %{host: host}}
        _ -> configure_host_resolution(options)
      end

    pool_id = :ets.new(__MODULE__, [:bag, :protected, read_concurrency: true])

    handler_ids =
      if initialized_properly do
        udps =
          for _ <- 1..options.pool_size do
            {:ok, udp} = UDP.open(udp_config)
            {:udp, udp}
          end

        :ets.insert(pool_id, udps)

        EventHandler.attach(
          metrics,
          self(),
          pool_id,
          options.mtu,
          options.prefix,
          options.formatter,
          options.global_tags
        )
      else
        []
      end

    {:ok,
     %{
       udp_config: udp_config,
       handler_ids: handler_ids,
       pool_id: pool_id,
       host: options.host,
       port: options.port,
       host_resolution_interval: options.host_resolution_interval,
       initialized_properly: initialized_properly
     }}
  end

  @impl true
  def handle_cast({:udp_error, old_udp, reason}, %{pool_id: pool_id} = state) do
    udps = :ets.lookup(pool_id, :udp)
    old_entry = {:udp, old_udp}

    if Enum.find(udps, fn entry -> entry == old_entry end) do
      Logger.error("Failed to publish metrics over UDP: #{inspect(reason)}")
      UDP.close(old_udp)
      :ets.delete_object(pool_id, old_entry)

      case UDP.open(state.udp_config) do
        {:ok, udp} ->
          :ets.insert(pool_id, {:udp, udp})
          {:noreply, state}

        {:error, reason} ->
          Logger.error("Failed to reopen UDP socket: #{inspect(reason)}")
          {:stop, {:udp_open_failed, reason}, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_pool_id, _from, %{pool_id: pool_id} = state) do
    {:reply, pool_id, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_info(:resolve_host, state) do
    %{
      host: host,
      udp_config: udp_config,
      host_resolution_interval: interval,
      initialized_properly: initialized_properly
    } =
      state

    new_state =
      case :inet.gethostbyname(host) do
        {:ok, hostent(h_addr_list: ips)} ->
          cond do
            !initialized_properly ->
              [ip_address | _] = ips
              Logger.debug("Resolved host #{host} to #{:inet.ntoa(ip_address)} IP address.")
              update_host(state, ip_address)

            Enum.member?(ips, udp_config.host) ->
              state
          end

        {:error, reason} ->
          if(!initialized_properly) do
            Logger.log(
              @log_level_warning,
              "Failed to resolve the hostname #{host}: #{inspect(reason)}. " <>
                "Previously resolved hostname was unsuccessful. The library will not send any metrics. " <>
                "Retrying to resolve it again in #{interval} milliseconds."
            )
          end

          Process.send_after(self(), :resolve_host, interval)
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end

  defp update_host(state, new_address) do
    %{pool_id: pool_id, udp_config: %{port: port} = udp_config} = state
    update_pool(pool_id, new_address, port)

    %{state | udp_config: %{udp_config | host: new_address}, initialized_properly: true}
  end

  defp configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family
       })
       when is_tuple(host) do
    {true, %{host: host, port: port, inet_address_family: inet_address_family}}
  end

  defp configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family,
         host_resolution_interval: interval
       })
       when is_integer(interval) do
    case :inet.gethostbyname(host, inet_address_family) do
      {:ok, hostent(h_addr_list: [ip | _ips])} ->
        {true, %{host: ip, port: port, inet_address_family: inet_address_family}}

      {:error, reason} ->
        Logger.log(
          @log_level_warning,
          "Failed to resolve the hostname #{host}: #{inspect(reason)}. " <>
            "Retrying to resolve it again in #{interval} milliseconds."
        )

        Process.send_after(self(), :resolve_host, interval)
        {false, %{host: nil, port: port, inet_address_family: inet_address_family}}
    end
  end

  defp configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family
       }) do
    case :inet.gethostbyname(host, inet_address_family) do
      {:ok, hostent(h_addr_list: [ip | _ips])} ->
        {true, %{host: ip, port: port, inet_address_family: inet_address_family}}

      {:error, reason} ->
        Logger.log(
          @log_level_warning,
          "Failed to resolve the hostname #{host}: #{inspect(reason)}. Metrics will not be sent at all."
        )

        {false, %{host: nil, port: port, inet_address_family: inet_address_family}}
    end
  end

  defp update_pool(pool_id, new_host, new_port) do
    pool_id
    |> :ets.tab2list()
    |> Enum.each(fn {:udp, udp} ->
      :ets.delete_object(pool_id, {:udp, udp})
      updated_udp = UDP.update(udp, new_host, new_port)
      :ets.insert(pool_id, {:udp, updated_udp})
    end)
  end
end
