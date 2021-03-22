defmodule TelemetryMetricsStatsd.UDP do
  @moduledoc false

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

  @spec open(config()) ::
          {:ok, t()} | {:error, reason :: term()}
  def open(config) do
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
        udp = struct(__MODULE__, Map.put(config, :socket, socket))
        {:ok, udp}

      {:error, _} = err ->
        err
    end
  end

  @spec send(t(), iodata()) :: :ok | {:error, reason :: term()}
  def send(%__MODULE__{host: host, port: port, socket: socket}, data) do
    case host do
      {:local, _} ->
        :gen_udp.send(socket, host, 0, data)

      _ ->
        :gen_udp.send(socket, host, port, data)
    end
  end

  @spec update(t(), :inet.hostname() | :inet.ip_address(), :inet.port_number()) :: t()
  def update(%__MODULE__{} = udp, new_host, new_port) do
    %__MODULE__{udp | host: new_host, port: new_port}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}) do
    :gen_udp.close(socket)
  end
end
