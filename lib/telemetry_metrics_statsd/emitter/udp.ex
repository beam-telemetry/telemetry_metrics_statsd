defmodule TelemetryMetricsStatsd.Emitter.UDP do
  alias TelemetryMetricsStatsd.Emitter.Congestion
  alias TelemetryMetricsStatsd.Options
  require Logger
  import Record
  use GenServer

  @moduledoc false

  @dialyzer [{:nowarn_function, append_metric: 2}, :no_improper_lists]

  defrecordp :buffer, size: 0, data: [], created_at: nil, count: 0
  defrecordp :hostent, extract(:hostent, from_lib: "kernel/include/inet.hrl")

  defstruct [
    :buffer,
    :destination,
    :dwell_time_check_interval,
    :emit_percentage,
    :emitted_metrics_count,
    :flush_timeout,
    :host,
    :host_resolution_interval,
    :inet_address_family,
    :max_queue_dwell_time_micros,
    :mtu,
    :port,
    :socket
  ]

  ## Client
  def start_link(%Options{} = options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl TelemetryMetricsStatsd.Emitter
  def emit(name, data) do
    GenServer.call(via_tuple(name), {:emit, data})
  end

  @impl TelemetryMetricsStatsd.Emitter
  def emit_internal(name, data) do
    GenServer.cast(via_tuple(name), {:emit_internal, data})
  end

  ## Server
  @impl GenServer
  def init(%Options{} = options) do
    Process.flag(:message_queue_data, :off_heap)
    udp_options = Map.take(options, ~w(host port inet_address_family host_resolution_interval)a)
    initial_state = struct!(__MODULE__, udp_options)

    with {:ok, state} <- configure_host_resolution(initial_state),
         {:ok, state} <- open_socket(state) do
      dwell_time_micros =
        if is_integer(options.max_queue_dwell_time) do
          options.max_queue_dwell_time * 1000
        end

      state = %__MODULE__{
        state
        | dwell_time_check_interval: options.dwell_time_check_interval,
          emit_percentage: 1.0,
          emitted_metrics_count: 0,
          flush_timeout: options.flush_timeout,
          max_queue_dwell_time_micros: dwell_time_micros,
          mtu: options.mtu
      }

      schedule_dwell_time_check(state)
      {:ok, state}
    end
  end

  @behaviour TelemetryMetricsStatsd.Emitter
  @impl GenServer
  def handle_call({:emit, data}, _from, %__MODULE__{} = state) do
    new_state =
      case add_to_buffer(state, data) do
        {:flush, buffers, new_buffer} when is_list(buffers) ->
          Enum.each(buffers, &write_to_socket!(state, &1))
          %__MODULE__{state | buffer: new_buffer}

        {:buffer, buffer} ->
          %__MODULE__{state | buffer: buffer}
      end

    {:reply, :ok, new_state, state.flush_timeout}
  end

  @impl true
  def handle_cast({:emit_internal, data}, %__MODULE__{} = state) do
    write_to_socket!(state, new_buffer(data))

    {:noreply, state, adjust_flush_timeout(state)}
  end

  @impl true
  def handle_info(:check_dwell_time, %__MODULE__{} = state) do
    schedule_dwell_time_check(state)
    send(self(), {:probe_dwell_time, dwell_timestamp()})
    {:noreply, state, adjust_flush_timeout(state)}
  end

  @impl true
  def handle_info({:probe_dwell_time, sent_at}, %__MODULE__{} = state) do
    dwell_time = dwell_time(sent_at)

    emit_percentage =
      Congestion.calculate_emit_percentage(
        state.emit_percentage,
        state.max_queue_dwell_time_micros,
        dwell_time
      )

    new_state = %__MODULE__{state | emit_percentage: emit_percentage}
    {:noreply, new_state, adjust_flush_timeout(new_state)}
  end

  @impl true
  def handle_info(:resolve_host, state) do
    %__MODULE__{destination: {current_address, _}} = state

    new_state =
      case resolve_host(state.host, state.inet_address_family) do
        {:ok, ip_addresses} ->
          if Enum.member?(ip_addresses, current_address) do
            state
          else
            [new_address | _] = ip_addresses
            update_host(state, new_address)
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to resolve the hostname #{inspect(state.host)}: #{inspect(reason)}. " <>
              "Using the previously resolved address of #{:inet.ntoa(current_address)}."
          )

          state
      end

    schedule_host_resolver(state)

    {:noreply, new_state, adjust_flush_timeout(state)}
  end

  @impl true
  def handle_info(:timeout, %__MODULE__{buffer: buffer(data: [_ | _]) = buffer} = state) do
    write_to_socket!(state, buffer)

    {:noreply, %__MODULE__{state | buffer: nil}}
  end

  def handle_info(:timeout, %__MODULE__{} = state) do
    {:noreply, %__MODULE__{state | buffer: nil}}
  end

  ## Private

  defp open_socket(%__MODULE__{} = state) do
    with {:ok, socket} <- :socket.open(state.inet_address_family, :dgram, :udp),
         :ok <- :socket.connect(socket, socket_options(state)) do
      {:ok, %__MODULE__{state | socket: socket}}
    end
  end

  defp close_socket(%__MODULE__{socket: nil} = state), do: {:ok, state}

  defp close_socket(%__MODULE__{} = state) do
    :socket.close(state.socket)
    %__MODULE__{state | socket: nil}
  end

  defp write_to_socket!(%__MODULE__{} = state, buffer(data: data)) do
    case :socket.send(state.socket, data) do
      :ok ->
        :ok

      {:error, :econnrefused} ->
        # TODO: Carrying over socket lib behavior, this seems like something we'd like to know about.
        :ok

      {:error, :eagain} ->
        # TODO: Carrying over socket lib behavior, this seems like something we'd like to know about.
        :ok

      {:error, reason} ->
        Logger.error("Failed to publish metrics over UDP: #{inspect(reason)}")

        exit(reason)
    end
  end

  defp adjust_flush_timeout(%__MODULE__{buffer: buffer(created_at: created_at)} = state) do
    now = System.system_time(:millisecond)
    elapsed = now - created_at
    remaining = state.flush_timeout - elapsed

    max(0, remaining)
  end

  defp adjust_flush_timeout(%__MODULE__{buffer: nil}) do
    :infinity
  end

  defp add_to_buffer(%__MODULE__{buffer: nil} = state, metric_data) do
    metric_size = byte_size(metric_data)

    cond do
      not Congestion.should_emit?(state.emit_percentage) ->
        {:buffer, state.buffer}

      metric_size >= state.mtu ->
        {:flush, [new_buffer(metric_data)], nil}

      true ->
        {:buffer, new_buffer(metric_data)}
    end
  end

  defp add_to_buffer(%__MODULE__{} = state, metric_data) do
    buffer(size: total_size) = appended_buffer = append_metric(state.buffer, metric_data)

    cond do
      not Congestion.should_emit?(state.emit_percentage) ->
        {:buffer, state.buffer}

      byte_size(metric_data) >= state.mtu ->
        {:flush, [state.buffer, new_buffer(metric_data)], nil}

      total_size == state.mtu ->
        {:flush, [appended_buffer], nil}

      total_size > state.mtu ->
        {to_emit, new_buffer} = flush_remaining_or_incoming(state.buffer, metric_data)

        {:flush, [to_emit], new_buffer}

      exceeded_flush_timeout?(state.buffer, state.flush_timeout) ->
        {to_emit, new_buffer} = flush_remaining_or_incoming(state.buffer, metric_data)

        {:flush, [to_emit], new_buffer}

      true ->
        {:buffer, appended_buffer}
    end
  end

  defp configure_host_resolution(%__MODULE__{host: host, port: port} = state)
       when is_tuple(host) do
    {:ok, %__MODULE__{state | destination: destination(host, port)}}
  end

  defp configure_host_resolution(%__MODULE__{} = state) do
    if is_integer(state.host_resolution_interval) do
      Process.send_after(self(), :resolve_host, state.host_resolution_interval)
    end

    with {:ok, ip_address} <- resolve_first_ip(state.host, state.inet_address_family) do
      {:ok, %__MODULE__{state | destination: destination(ip_address, state.port)}}
    end
  end

  defp append_metric(buffer(data: data, count: count, size: size) = old_buffer, metric_data) do
    # Include 1 byte for the newline
    total_size = size + byte_size(metric_data) + 1
    buffer(old_buffer, data: [data, "\n" | metric_data], count: count + 1, size: total_size)
  end

  defp flush_remaining_or_incoming(data, metric_data) do
    {data, new_buffer(metric_data)}
  end

  defp new_buffer(data) do
    buffer(
      size: byte_size(data),
      data: List.wrap(data),
      created_at: System.system_time(:millisecond),
      count: 1
    )
  end

  defp resolve_host(hostname, address_family) do
    with {:ok, hostent(h_addr_list: ip_addresses)} <-
           :inet.gethostbyname(hostname, address_family) do
      {:ok, ip_addresses}
    end
  end

  defp resolve_first_ip(hostname, address_family) do
    with {:ok, ip_addresses} <- resolve_host(hostname, address_family) do
      {:ok, List.first(ip_addresses)}
    end
  end

  def supervisor_name(name) do
    Module.concat([PartitionSupervisor, For, name])
  end

  defp update_host(%__MODULE__{} = state, new_address) do
    state = %{state | destination: destination(new_address, state.port)}

    with {:ok, state} <- close_socket(state) do
      open_socket(state)
    end
  end

  def via_tuple(name) do
    {:via, PartitionSupervisor, {supervisor_name(name), self()}}
  end

  defp destination(host, port) do
    {host, port}
  end

  defp exceeded_flush_timeout?(buffer(created_at: created_at), flush_timeout) do
    current_time = System.system_time(:millisecond)
    current_time - created_at > flush_timeout
  end

  defp schedule_host_resolver(%__MODULE__{host_resolution_interval: host_resolution_interval})
       when is_integer(host_resolution_interval) do
    Process.send_after(self(), :resolve_host, host_resolution_interval)
  end

  defp schedule_host_resolver(_), do: :ok

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

  defp socket_options(%__MODULE__{} = state) do
    {ip_address, port} = state.destination
    %{family: state.inet_address_family, port: port, addr: ip_address}
  end
end
