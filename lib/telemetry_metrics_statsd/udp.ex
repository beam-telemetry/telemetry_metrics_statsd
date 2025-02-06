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
          optional(:port) => :inet.port_number(),
          optional(:inet_address_family) => boolean()
        }

  @spec open(config()) ::
          {:ok, t()} | {:error, reason :: term()}
  def open(config) do
    opts = [{:active, false}]

    opts =
      Enum.reduce(config, opts, fn
        {:host, {:local, _}}, opts -> [:local | opts]
        {:inet_address_family, value}, opts -> [value | opts]
        {_key, _value}, opts -> opts
      end)

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
    |> handle_send_result()
  end

  @spec update(t(), :inet.hostname() | :inet.ip_address(), :inet.port_number()) :: t()
  def update(%__MODULE__{} = udp, new_host, new_port) do
    %__MODULE__{udp | host: new_host, port: new_port}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}) do
    :gen_udp.close(socket)
  end

  defp handle_send_result({:error, :eagain}) do
    # TODO: report packed drop?
    :ok
  end

  defp handle_send_result(result) do
    result
  end
end
