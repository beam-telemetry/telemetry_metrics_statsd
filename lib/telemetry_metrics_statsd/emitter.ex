defmodule TelemetryMetricsStatsd.Emitter do
  use GenServer

  require Logger
  alias TelemetryMetricsStatsd.Emit
  alias TelemetryMetricsStatsd.Host
  alias TelemetryMetricsStatsd.UDP

  defstruct [:options, :udp, :udp_config, drop_count: 0]

  ## OTP

  def child_spec([i, options]) do
    %{
      id: {__MODULE__, i},
      start: {__MODULE__, :start_link, [options]},
      restart: :permanent
    }
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  ## Client

  def event(server, measurement, metadata, metrics) do
    GenServer.cast(server, {:event, measurement, metadata, metrics})
  end

  ## Server

  def init(options) do
    # Optimization: Keep our possibly large queue off the heap
    Process.flag(:message_queue_data, :off_heap)

    udp_config =
      case options.host do
        {:local, _} = host -> %{host: host}
        _ -> Host.configure_host_resolution(options)
      end

    {:ok, udp} = UDP.open(udp_config)

    state = %__MODULE__{options: options, udp: udp, udp_config: udp_config}

    {:ok, state}
  end

  def handle_cast({:event, measurement, metadata, metrics}, %__MODULE__{} = state) do
    state =
      if should_drop?(state.options.emitter_drop_threshold) do
        # Drop the metric and increment the drop_count
        %__MODULE__{state | drop_count: state.drop_count + 1}
      else
        Emit.emit(state.udp, self(), measurement, metadata, metrics, state.options)
        maybe_log_drops(state)
      end

    {:noreply, state}
  end

  def handle_cast({:udp_error, _, reason}, %__MODULE__{} = state) do
    # UDP Error, exit and restart
    {:stop, {:udp_error, reason}, state}
  end

  def handle_info(:resolve_host, state) do
    if Host.configuration_valid?(state.options.host, state.udp_config.host) do
      Host.schedule_resolve(state.options.host_resolution_interval)
      {:noreply, state}
    else
      # UDP configuration is no longer valid, exit and restart
      {:stop, {:shutdown, :host_lost}, state}
    end
  end

  ## Private

  defp maybe_log_drops(%__MODULE__{drop_count: 0} = state) do
    state
  end

  defp maybe_log_drops(%__MODULE__{} = state) do
    Logger.warning("Emitter #{inspect(self())} dropped #{state.drop_count} messages")
    %__MODULE__{state | drop_count: 0}
  end

  defp should_drop?(:disabled) do
    false
  end

  defp should_drop?(threshold) do
    {:message_queue_len, length} = Process.info(self(), :message_queue_len)
    threshold < length
  end
end
