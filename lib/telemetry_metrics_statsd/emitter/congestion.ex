defmodule TelemetryMetricsStatsd.Emitter.Congestion do
  @moduledoc """
  Congestion handling

  This module implements congestion flow control using the additive increase / multiplicative
  decrease algorithm. When congestion is detected, the percentage of metrics being emitted is
  reduced by half. When congestion alleviates, every call to increases amount of metrics emitted
  by 1%.

  This algorithm has a floor of 0.1% of metrics emitted. Continued failures won't lower the
  percentage of metrics emitted
  """

  @type emit_percentage :: float()
  @type elapsed_microseconds :: non_neg_integer()
  @type microseconds :: non_neg_integer()
  @type message_queue_length :: non_neg_integer()

  @emit_percentage_increment 0.01
  @emit_percentage_decrement 0.5
  @minumum_emit_percentage 0.001

  require Logger

  @doc """
  Returns true if the metric should be emitted
  end
  """
  @spec should_emit?(emit_percentage) :: boolean()
  def should_emit?(emit_percentage) do
    :rand.uniform() <= emit_percentage
  end

  @spec calculate_emit_percentage(
          emit_percentage(),
          max_dwell_time_millis :: microseconds(),
          observed_dweel_time_micros :: elapsed_microseconds()
        ) :: emit_percentage()
  def calculate_emit_percentage(
        orig_emit_percentage,
        max_dwell_time_micros,
        observed_dwell_time_micros
      )
      when is_integer(max_dwell_time_micros) and is_integer(observed_dwell_time_micros) and
             is_float(orig_emit_percentage) do
    # Using additive increase / multiplicative decrease algorithm to ensure that
    # we arrive at an optimal value for the dwell time

    new_emit_percentage =
      cond do
        observed_dwell_time_micros > max_dwell_time_micros ->
          max(
            orig_emit_percentage * (1 - @emit_percentage_decrement),
            @minumum_emit_percentage
          )

        observed_dwell_time_micros <= max_dwell_time_micros ->
          min(orig_emit_percentage + @emit_percentage_increment, 1.0)

        true ->
          orig_emit_percentage
      end

    :telemetry.execute([:telemetry_metrics_statsd, :congestion, :dwell_time], %{
      duration: observed_dwell_time_micros
    })

    cond do
      new_emit_percentage > orig_emit_percentage ->
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :increase],
          %{count: 1, value: new_emit_percentage}
        )

        Logger.info(
          "Emitter #{inspect(self())} raising emit percentage to #{new_emit_percentage * 100}%"
        )

      new_emit_percentage < orig_emit_percentage ->
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :decrease],
          %{count: 1, value: new_emit_percentage}
        )

        Logger.critical(
          "Dwell time for emitter #{inspect(self())} of #{observed_dwell_time_micros}us exceeds #{max_dwell_time_micros}us. " <>
            "Now sampling at #{new_emit_percentage * 100}%"
        )

      true ->
        :ok
    end

    new_emit_percentage
  end

  def calculate_emit_percentage(emit_percentage, _, _) do
    emit_percentage
  end
end
