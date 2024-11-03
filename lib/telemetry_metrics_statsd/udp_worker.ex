defmodule TelemetryMetricsStatsd.UDPWorker do
  @moduledoc false

  use GenServer

  alias TelemetryMetricsStatsd.{UDP, Packet, CounterOk, CounterError}

  @default_buffer_flush_ms 1000
  @default_max_datagram_size 1432

  defstruct [
    :reporter,
    :pool_id,
    :buffered_datagram,
    :buffer_flush_ms,
    :max_datagram_size
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    buffer_flush_ms = opts[:buffer_flush_ms] || @default_buffer_flush_ms

    state = %__MODULE__{
      reporter: opts[:reporter],
      pool_id: opts[:pool_id],
      buffered_datagram: [],
      buffer_flush_ms: buffer_flush_ms,
      max_datagram_size: opts[:max_datagram_size] || @default_max_datagram_size
    }

    schedule_flush(state)

    {:ok, state}
  end

  def publish_datagrams(pid, datagrams) do
    GenServer.call(pid, {:publish_datagrams, datagrams})
  end

  @impl true
  def handle_call({:publish_datagrams, datagrams}, _from, state) do
    new_buffered_datagrams =
      Enum.reduce(datagrams, state.buffered_datagram, &do_append_datagram/2)

    cond do
      state.buffer_flush_ms == 0 ->
        for packet <- Packet.build_packets(datagrams, state.max_datagram_size, "\n") do
          maybe_send_udp_datagrams(state, packet)
        end

        {:reply, :ok, %{state | buffered_datagram: []}}

      Enum.any?(datagrams, fn datagram -> IO.iodata_length(datagram) > state.max_datagram_size end) ->
        {:reply,
         {:error, "Payload is too big (more than #{state.max_datagram_size} bytes), dropped."},
         state}

      IO.iodata_length(new_buffered_datagrams) > state.max_datagram_size ->
        maybe_send_udp_datagrams(state)

        {:reply, :ok, %{state | buffered_datagram: datagrams}}

      true ->
        {:reply, :ok, %{state | buffered_datagram: new_buffered_datagrams}}
    end
  end

  defp maybe_send_udp_datagrams(state, datagrams \\ nil) do
    datagrams_to_send = datagrams || state.buffered_datagram

    if datagrams_to_send != [] do
      case TelemetryMetricsStatsd.get_udp(state.pool_id) do
        {:ok, udp} ->
          case UDP.send(udp, datagrams_to_send) do
            :ok ->
              CounterOk.increment()

              :ok

            {:error, reason} ->
              CounterError.increment()

              TelemetryMetricsStatsd.udp_error(state.reporter, udp, reason)
          end

        :error ->
          :ok
      end
    else
      :ok
    end
  end

  @impl true
  def handle_info(:buffer_flush, state) do
    if state.buffered_datagram != [] do
      maybe_send_udp_datagrams(state)
    end

    schedule_flush(state)

    {:noreply, %{state | buffered_datagram: []}}
  end

  defp schedule_flush(%{buffer_flush_ms: buffer_flush_ms}) when buffer_flush_ms > 0,
    do: Process.send_after(self(), :buffer_flush, buffer_flush_ms)

  defp schedule_flush(_), do: :ok

  defp do_append_datagram([], first_datagram), do: first_datagram
  defp do_append_datagram(current_buffer, datagram), do: [current_buffer, "\n", datagram]
end
