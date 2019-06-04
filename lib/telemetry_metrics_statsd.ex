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

  By default the reporter sends metrics to localhost:8125 - both hostname and port number can be
  configured using the `:host` and `:port` options.

  Note that the reporter doesn't aggregate metrics in-process - it sends metric updates to StatsD
  whenever a relevant Telemetry event is emitted.

  ## Translation between Telemetry.Metrics and StatsD

  In this section we walk through how the Telemetry.Metrics metric definitions are mapped to StatsD
  metrics and their types at runtime.

  Telemetry.Metrics metric names are translated as follows:
    * if the metric name was provided as a string, e.g. `"http.request.count"`, it is sent to
      StastD server as-is
    * if the metric name was provided as a list of atoms, e.g. `[:http, :request, :count]`, it is
      first converted to a string by joiging the segments with dots. In this example, the StatsD
      metric name would be `"http.request.count"` as well

  The names look a little bit different if metric tags are used - since not all StatsD
  implementations allow explicit tagging, tag values are appended as consecutive segments of the
  metric name. For example, given the definition

      counter("db.query.count", tags: [:table, :operation])

  and the event

      :telemetry.execute([:db, :query], %{}, %{table: "users", operation: "select"})

  the StastD metric name would be `"db.query.count.users.select"`. Note that the tag values are
  appended to the base metric name in the order they were declared in the metric definition.

  Now to the metric types!

  ### Counter

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

  ### Last value

  Last value metric is represented as a StastD gauge, whose values are always set to the value
  of the measurement from the most recent event. With the following metric definition

      last_value("vm.memory.total")

  and the event

      :telemetry.execute([:vm, :memory], %{total: 1024})

  the following metric update would be send to StatsD

      "vm.memory.total:1024|g"

  ### Sum

  Sum metric is also represented as a gauge - the difference is that it always changes relatively
  and is never set to an absolute value. Given metric definition below

      sum("http.request.payload_size")

  and the event

      :telemetry.execute([:http, :request], %{payload_size: 1076})

  the following line would be send to StatsD

      "http.request.count:+1076|g"

  When the measurement is negative, the StatsD gauge is decreased accordingly.

  ### Distribution

  There is no metric in StatsD (or at least in the
  [Etsy implementation](https://github.com/statsd/statsd/blob/master/docs/metric_types.md))
  equivalent to Telemetry.Metrics distribution. However, since the goal of a distribution metric
  is to gain an insight into statistics of data points, this reporter translates it to StatsD
  timer. For example, given the following metric definition

      distribution("http.request.duration", buckets: [0])

  and the event

      :telemetry.execute([:http, :request], %{duration: 120})

  the following line would be send to StatsD

      "http.request.duration:120|ms"

  Since StatsD timers don't maintain a histogram of values, **distribution's `:buckets` option
  has no meaning in case of this reporter**.

  > Note: all floating point measurements are rounded to the nearest integer.

  ## Prefixing metric names

  Since not all the StatsD implementations provide a proper tagging system, sometimes it's convenient
  to prefix all metric names with particular value, to group them by the name of the service,
  the host, or something else. You can use `:prefix` option to provide a prefix which will be
  prepended to all metrics published by the reporter.

  ## Maximum datagram size

  Metrics are sent to StatsD over UDP, so it's important that the size of the datagram does not
  exceed the Maximum Transmission Unit, or MTU, of the link, so that no data is lost on the way.
  By default the reporter will break up the datagrams at 512 bytes, but this is configurable via
  the `:mtu` option.
  """

  use GenServer

  require Logger

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{EventHandler, UDP}

  @type tag_format :: :name | :datadog
  @type option ::
          {:port, :inet.port_number()}
          | {:host, String.t()}
          | {:metrics, [Metrics.t()]}
          | {:mtu, non_neg_integer()}
          | {:prefix, String.t()}
          | {:tag_format, tag_format()}
  @type options :: [option]

  @default_port 8125
  @default_mtu 512
  @default_tag_format :name

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
  * `:metrics` - a list of Telemetry.Metrics metric definitions which will be published by the
    reporter
  * `:host` - hostname of the StatsD server. Defaults to `"localhost"`.
  * `:port` - port number of the StatsD server. Defaults to `8125`.
  * `:prefix` - a prefix prepended to the name of each metric published by the reporter. Defaults
    to `nil`.
  * `:mtu` - Maximum Transmission Unit of the link between your application and the StatsD server in
    bytes. This value should not be greater than the actual MTU since this could lead to the data loss
    when the metrics are published. Defaults to `512`.

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
    GenServer.start_link(__MODULE__, options)
  end

  @doc false
  @spec get_udp(pid()) :: UDP.t()
  def get_udp(reporter) do
    GenServer.call(reporter, :get_udp)
  end

  @doc false
  @spec udp_error(pid(), UDP.t(), reason :: term) :: :ok
  def udp_error(reporter, udp, reason) do
    GenServer.cast(reporter, {:udp_error, udp, reason})
  end

  @impl true
  def init(options) do
    metrics = Keyword.fetch!(options, :metrics)
    port = Keyword.get(options, :port, @default_port)
    host = Keyword.get(options, :host, "localhost") |> to_charlist()
    mtu = Keyword.get(options, :mtu, @default_mtu)
    tag_format = Keyword.get(options, :tag_format, @default_tag_format)
    prefix = Keyword.get(options, :prefix)

    case UDP.open(host, port) do
      {:ok, udp} ->
        Process.flag(:trap_exit, true)
        handler_ids = EventHandler.attach(metrics, self(), mtu, prefix, tag_format)
        {:ok, %{udp: udp, handler_ids: handler_ids, host: host, port: port}}

      {:error, reason} ->
        {:error, {:udp_open_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_udp, _from, state) do
    {:reply, state.udp, state}
  end

  @impl true
  def handle_cast({:udp_error, udp, reason}, %{udp: udp} = state) do
    Logger.error("Failed to publish metrics over UDP: #{inspect(reason)}")

    case UDP.open(state.host, state.port) do
      {:ok, udp} ->
        {:noreply, %{state | udp: udp}}

      {:error, reason} ->
        Logger.error("Failed to reopen UDP socket: #{inspect(reason)}")
        {:stop, {:udp_open_failed, reason}, state}
    end
  end

  def handle_cast({:udp_error, _, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end
end
