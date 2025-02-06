defmodule TelemetryMetricsStatsd.EventHandler do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsStatsd.{Emit, Formatter}

  @spec attach(
          [Metrics.t()],
          reporter :: pid(),
          pool_id :: :ets.tid(),
          mtu :: non_neg_integer(),
          prefix :: String.t() | nil,
          formatter :: Formatter.t(),
          global_tags :: Keyword.t()
        ) :: [
          :telemetry.handler_id()
        ]
  def attach(metrics, reporter, pool_id, mtu, prefix, formatter, global_tags) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name, reporter)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          reporter: reporter,
          pool_id: pool_id,
          metrics: metrics,
          mtu: mtu,
          prefix: prefix,
          formatter: formatter,
          global_tags: global_tags
        })

      handler_id
    end
  end

  @spec detach([:telemetry.handler_id()]) :: :ok
  def detach(handler_ids) do
    for handler_id <- handler_ids do
      :telemetry.detach(handler_id)
    end

    :ok
  end

  def handle_event(_event, measurements, metadata, %{
        reporter: reporter,
        pool_id: pool_id,
        metrics: metrics,
        mtu: _mtu,
        prefix: _prefix,
        formatter: _formatter_mod,
        global_tags: _global_tags
      } = options) do
    case TelemetryMetricsStatsd.get_udp(pool_id) do
      {:ok, udp} ->
        Emit.emit(udp, reporter, measurements, metadata, metrics, options)

      :error ->
        :ok
    end
  end

  @spec handler_id(:telemetry.event_name(), reporter :: pid) :: :telemetry.handler_id()
  defp handler_id(event_name, reporter) do
    {__MODULE__, reporter, event_name}
  end

end
