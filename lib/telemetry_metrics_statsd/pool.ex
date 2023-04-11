defmodule TelemetryMetricsStatsd.Pool do
  @moduledoc false

  @pool __MODULE__

  alias TelemetryMetricsStatsd.UDP

  def new(pool_size, udp_config) do
    options = [
      workers: pool_size,
      worker: {UDP, udp_config}
    ]

    pool_id =
      :rand.bytes(10)
      |> Base.encode16()
      |> String.to_atom()

    case :wpool.start_sup_pool(pool_id, options) do
      {:ok, _pid} -> {:ok, pool_id}
      other -> other
    end
  end

  def send(pool_id, packet) do
    :wpool.cast(pool_id, {:send, packet})
  end

  def get_udp(pool_id) do
    :wpool_pool.random_worker(pool_id)
  end

  def get_workers(pool_id) do
    :wpool.get_workers(pool_id)
  end

  def update(pool_id, new_host, new_port) do
    get_workers(pool_id)
    |> Enum.each(fn name ->
      UDP.update(name, new_host, new_port)
    end)
  end
end
