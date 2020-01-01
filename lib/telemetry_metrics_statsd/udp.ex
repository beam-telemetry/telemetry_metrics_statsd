defmodule TelemetryMetricsStatsd.UDP do
  @moduledoc false

  defstruct [:host, :port, :socket]

  @opaque t :: %__MODULE__{
            host: :inet.hostname() | :inet.ip_address(),
            port: :inet.port_number(),
            socket: :gen_udp.socket()
          }

  @spec open(:inet.hostname() | :inet.ip_address(), :inet.port_number()) ::
          {:ok, t()} | {:error, reason :: term()}
  def open(host, port) do
    case :gen_udp.open(0) do
      {:ok, socket} ->
        {:ok, %__MODULE__{host: host, port: port, socket: socket}}

      {:error, _} = err ->
        err
    end
  end

  @spec send(t(), iodata()) :: :ok | {:error, reason :: term()}
  def send(%__MODULE__{host: host, port: port, socket: socket}, data) do
    :gen_udp.send(socket, host, port, data)
  end
end
