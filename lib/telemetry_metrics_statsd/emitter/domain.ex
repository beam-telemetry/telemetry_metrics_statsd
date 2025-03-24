defmodule TelemetryMetricsStatsd.Emitter.Domain do
  @moduledoc false

  alias TelemetryMetricsStatsd.Emitter.Congestion
  alias TelemetryMetricsStatsd.Options
  use GenServer

  @behaviour TelemetryMetricsStatsd.Emitter

  defstruct [
    :dwell_time_check_interval,
    :emit_percentage,
    :max_queue_dwell_time_micros,
    :path,
    :socket
  ]

  # Public
  @impl true
  def emit(name, metric) do
    GenServer.call(via_tuple(name), {:emit, metric})
  end

  @impl true
  def emit_internal(name, metric) do
    GenServer.call(via_tuple(name), {:emit_internal, metric})
  end

  def supervisor_name(name) do
    Module.concat([PartitionSupervisor, For, name])
  end

  def via_tuple(name) do
    {:via, PartitionSupervisor, {supervisor_name(name), self()}}
  end

  def start_link(%Options{} = options) do
    GenServer.start_link(__MODULE__, options)
  end

  # OTP Callbacks

  @impl GenServer
  def init(%Options{} = options) do
    # This GenServer basically shuffles messages from the calling process into the receiving socket,
    # which appears to be the exact case for off heap message queue data.
    Process.flag(:message_queue_data, :off_heap)

    {:local, socket_path} = options.host

    socket_path = List.to_string(socket_path)

    max_queue_dwell_time_micros =
      if is_integer(options.max_queue_dwell_time) do
        options.max_queue_dwell_time * 1000
      end

    with {:ok, socket} = :socket.open(:local, :dgram),
         :ok <- :socket.connect(socket, %{family: :local, path: socket_path}) do
      state = %__MODULE__{
        dwell_time_check_interval: options.dwell_time_check_interval,
        emit_percentage: 1.0,
        max_queue_dwell_time_micros: max_queue_dwell_time_micros,
        path: socket_path,
        socket: socket
      }

      schedule_dwell_time_check(state)
      {:ok, state}
    end
  end

  @impl true
  def handle_call({:emit, metric}, _from, %__MODULE__{} = state) do
    case write_to_socket(state, metric, :normal) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:stop, reason, :ok, state}
    end
  end

  def handle_call({:emit_internal, metric}, _from, %__MODULE__{} = state) do
    case write_to_socket(state, metric, :internal) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:stop, reason, :ok, state}
    end
  end

  @impl true
  def handle_info(:check_dwell_time, %__MODULE__{} = state) do
    send(self(), {:probe_dwell_time, dwell_timestamp()})
    {:noreply, state}
  end

  @impl true
  def handle_info({:probe_dwell_time, sent_at}, %__MODULE__{} = state) do
    schedule_dwell_time_check(state)

    dwell_time = dwell_time(sent_at)

    emit_percentage =
      Congestion.calculate_emit_percentage(
        state.emit_percentage,
        state.max_queue_dwell_time_micros,
        dwell_time
      )

    {:noreply, %__MODULE__{state | emit_percentage: emit_percentage}}
  end

  # Private
  defp write_to_socket(%__MODULE__{} = state, data, :internal) do
    :socket.send(state.socket, data)
  end

  defp write_to_socket(%__MODULE__{} = state, data, _) do
    if Congestion.should_emit?(state.emit_percentage) do
      :socket.send(state.socket, data)
    else
      :ok
    end
  end

  defp schedule_dwell_time_check(
         %__MODULE__{max_queue_dwell_time_micros: max_queue_dwell_time_micros} = state
       )
       when is_integer(max_queue_dwell_time_micros) do
    Process.send_after(self(), :check_dwell_time, state.dwell_time_check_interval)
  end

  defp schedule_dwell_time_check(_) do
    :ok
  end

  defp dwell_timestamp() do
    System.system_time(:microsecond)
  end

  defp dwell_time(sent_at) do
    dwell_timestamp() - sent_at
  end
end
