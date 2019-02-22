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

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{EventHandler, UDP}

  @type option ::
          {:port, :inet.port_number()} | {:host, String.t()} | {:metrics, [Metrics.t()]}
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
          payload :: binary()
        ) :: :ok
  def report(reporter, payload) do
    # Use call to make sure that the reporter is alive.
    GenServer.call(reporter, {:report, payload})
  end

  @impl true
  def init(options) do
    metrics = Keyword.fetch!(options, :metrics)
    port = Keyword.get(options, :port, @default_port)
    host = Keyword.get(options, :host, "localhost") |> to_charlist()

    case UDP.open(host, port) do
      {:ok, udp} ->
        handler_ids = EventHandler.attach(metrics, self())
        {:ok, %{udp: udp, handler_ids: handler_ids}}

      {:error, reason} ->
        {:error, {:udp_open_failed, reason}}
    end
  end

  @impl true
  def handle_call({:report, _payload} = report_data, _from, state) do
    GenServer.cast(self(), report_data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:report, payload}, state) do
    :ok = UDP.send(state.udp, payload)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end
end
