defmodule TelemetryMetricsStatsd.UDP do
  @moduledoc false

  use GenServer

  defstruct [:host, :port, :socket]

  @opaque t :: %__MODULE__{
            host: :inet.hostname() | :inet.ip_address() | :inet.local_address(),
            port: :inet.port_number(),
            socket: :gen_udp.socket()
          }

  @type config :: %{
          :host => :inet.hostname() | :inet.ip_address() | :inet.local_address(),
          optional(:port) => :inet.port_number()
        }

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @spec send(pid, iodata) :: :ok | {:error, term}
  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  def update(pid, new_host, new_port) do
    GenServer.call(pid, {:update, new_host, new_port})
  end

  def close(pid) do
    GenServer.call(pid, :close)
  end


  @impl true
  def init(config) do
    opts = [active: false]

    opts =
      case config.host do
        {:local, _} ->
          [:local | opts]

        _ ->
          opts
      end

    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        state = struct(__MODULE__, Map.put(config, :socket, socket))
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:update, new_host, new_port}, _from, state) do
    {:noreply, %__MODULE__{state | host: new_host, port: new_port}}
  end

  @impl true
  def handle_call({:send, data}, _from, %__MODULE__{host: host, port: port, socket: socket} = state) do
    result =
      case host do
        {:local, _} ->
          :gen_udp.send(socket, host, 0, data)

        _ ->
          :gen_udp.send(socket, host, port, data)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:close, _from, %__MODULE__{socket: socket} = state) do
    :gen_udp.close(socket)
    {:reply, :ok, state}
  end
end
