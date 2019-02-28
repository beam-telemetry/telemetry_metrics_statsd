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

  require Logger

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{EventHandler, UDP}

  @type option ::
          {:port, :inet.port_number()}
          | {:host, String.t()}
          | {:metrics, [Metrics.t()]}
          | {:mtu, non_neg_integer()}
  @type options :: [option]

  @default_port 8125
  @default_mtu 512

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

  @spec get_udp(pid()) :: UDP.t()
  def get_udp(reporter) do
    GenServer.call(reporter, :get_udp)
  end

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

    case UDP.open(host, port) do
      {:ok, udp} ->
        handler_ids = EventHandler.attach(metrics, self(), mtu)
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

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end
end
