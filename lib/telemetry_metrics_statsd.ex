defmodule TelemetryMetricsStatsd do
  @moduledoc """
  `Telemetry.Metrics` reporter sending metrics to StatsD.
  """

  # TODO:
  # * docs
  # * make sure that handlers are detached properly on failure (i.e. read terminate/2 docs)
  # * MTU handling
  # * custom formatters
  # * some kind of pooling?

  use GenServer

  alias TelemetryMetricsStatsd.{EventHandler, Formatter, UDP}

  @type option ::
          {:port, :inet.port_number()} | {:host, String.t()} | {:metrics, [Telemetry.Metrics.t()]}
  @type options :: [option]

  @default_port 8125

  @doc """
  Reporter's child spec.

  This function allows you to start the reporter under a supervisor like this:

      children = [
        {TelemetryMetricsStatsd, options}
      ]

  where options is of type `t:options/0`.
  """
  @spec child_spec(options) :: Supervisor.child_spec()
  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}}
  end

  @doc """
  Starts a reporter and links it to the calling process.
  """
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @doc false
  @spec report(
          pid(),
          Telemetry.Metrics.normalized_metric_name(),
          :telemetry.event_value(),
          :telemetry.event_metadata()
        ) :: :ok
  def report(reporter, metric_name, event_value, metadata) do
    # Use call to make sure that the reporter is alive.
    GenServer.call(reporter, {:report, metric_name, event_value, metadata})
  end

  @impl true
  def init(options) do
    metrics = Keyword.fetch!(options, :metrics)
    port = Keyword.get(options, :port, @default_port)
    host = Keyword.get(options, :host, "localhost") |> to_charlist()

    case UDP.open(host, port) do
      {:ok, udp} ->
        EventHandler.attach(metrics, self())
        metrics_map = metrics |> Enum.map(&{&1.name, &1}) |> Enum.into(%{})
        {:ok, %{udp: udp, metrics: metrics_map}}

      {:error, reason} ->
        {:error, {:udp_open_failed, reason}}
    end
  end

  @impl true
  def handle_call({:report, _metric_name, _value, _metadata} = report_data, _from, state) do
    GenServer.cast(self(), report_data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:report, metric_name, value, metadata}, state) do
    metric = Map.fetch!(state.metrics, metric_name)

    # The order of tags needs to be preserved so that the final metric name is built correctly.
    tags = Enum.map(metric.tags, &{&1, Map.fetch!(metadata, &1)})
    payload = Formatter.format(metric, value, tags)
    :ok = UDP.send(state.udp, payload)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    state.metrics
    |> Map.values()
    |> EventHandler.detach(self())

    :ok
  end
end
