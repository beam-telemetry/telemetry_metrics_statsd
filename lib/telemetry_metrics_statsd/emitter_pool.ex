defmodule TelemetryMetricsStatsd.EmitterPool do
  use Supervisor

  alias TelemetryMetricsStatsd.Emitter

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options)
  end

  def init(options) do
    children =
      for i <- 1..options.emitter_pool do
        {Emitter, [i, options]}
      end

    attach_all(options.metrics)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def attach_all(metrics) do
    metrics_by_event = Enum.group_by(metrics, & &1.event_name)

    for {event_name, metrics} <- metrics_by_event do
      handler_id = handler_id(event_name)

      # Take over if there's a stale handler for this id.
      :ok = :telemetry.detach(handler_id)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{metrics: metrics})

      handler_id
    end
  end

  @spec handler_id(:telemetry.event_name()) :: :telemetry.handler_id()
  defp handler_id(event_name) do
    {__MODULE__, event_name}
  end

  def handle_event(_event, measurements, metadata, %{metrics: metrics}) do
    Emitter.event(get_emitter(), measurements, metadata, metrics)
  end

  defp get_emitter() do
    case Enum.random(Supervisor.which_children(self())) do
      {_, pid, _, _} when is_pid(pid) ->
        pid

      _ ->
        get_emitter()
    end
  end
end
