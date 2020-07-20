defmodule TelemetryMetricsStatsd.UDP do
  @moduledoc false

  defstruct [:host, :port, :socket, :socket_path]

  @opaque t :: %__MODULE__{
            host: :inet.hostname() | :inet.ip_address(),
            port: :inet.port_number(),
            socket: :gen_udp.socket(),
            socket_path: binary()
          }

  @type ip_config :: %{
          host: :inet.hostname() | :inet.ip_address(),
          port: :inet.port_number()
        }
  @type local_config :: %{
          socket_path: binary()
        }
  @type config :: ip_config() | local_config()

  @spec open(config()) ::
          {:ok, t()} | {:error, reason :: term()}
  def open(config) do
    opts = if config[:socket_path], do: [:local], else: []

    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        {:ok,
         %__MODULE__{
           host: config[:host],
           port: config[:port],
           socket: socket,
           socket_path: config[:socket_path]
         }}

      {:error, _} = err ->
        err
    end
  end

  @spec send(t(), iodata()) :: :ok | {:error, reason :: term()}
  def send(%__MODULE__{host: host, port: port, socket: socket, socket_path: socket_path}, data) do
    if socket_path do
      :gen_udp.send(socket, {:local, socket_path}, 0, data)
    else
      :gen_udp.send(socket, host, port, data)
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}) do
    :gen_udp.close(socket)
  end
end
