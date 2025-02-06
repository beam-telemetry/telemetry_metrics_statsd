defmodule TelemetryMetricsStatsd.UDP do
  @moduledoc false

  defstruct [:socket]

  @opaque t :: %__MODULE__{
            socket: :socket.socket()
          }

  @type config :: %{
          :host => :inet.hostname() | :inet.ip_address() | :inet.local_address(),
          optional(:port) => :inet.port_number(),
          optional(:inet_address_family) => boolean()
        }

  @spec open(config()) ::
          {:ok, t()} | {:error, reason :: term()}
  def open(config) do
    {domain, address} =
      case config.host do
        {:local, path} ->
          {:local, %{family: :local, path: path}}

        ip when tuple_size(ip) == 4 ->
          {:inet, %{family: :inet, port: config.port, addr: ip}}

        ip when tuple_size(ip) == 8 ->
          {:inet, %{family: :inet6, port: config.port, addr: ip}}
      end

    with {:ok, socket} <- :socket.open(domain, :dgram),
         :ok <- :socket.connect(socket, address) do
      udp = struct(__MODULE__, Map.put(config, :socket, socket))
      {:ok, udp}
    end
  end

  @spec send(t(), iodata()) :: :ok | {:error, reason :: term()}
  def send(%__MODULE__{socket: socket}, data) do
    :socket.send(socket, data)
    |> handle_send_result()
  end

  @spec update(t(), :inet.hostname() | :inet.ip_address(), :inet.port_number()) :: t()
  def update(%__MODULE__{} = udp, new_host, new_port) do
    #%__MODULE__{udp | host: new_host, port: new_port}
    udp
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}) do
    :socket.close(socket)
  end

  defp handle_send_result({:error, :eagain}) do
    # TODO: report packed drop?
    :ok
  end

  defp handle_send_result(result) do
    result
  end
end
