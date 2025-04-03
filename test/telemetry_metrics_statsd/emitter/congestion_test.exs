defmodule TelemetryMetricsStatsd.Emitter.CongestionTest do
  alias TelemetryMetricsStatsd.Emitter.Congestion

  use ExUnit.Case
  use ExUnitProperties
  use Patch

  import ExUnit.CaptureLog

  describe "adjusting emit percentage" do
    setup do
      orig_level = Logger.level()
      Logger.configure(level: :none)

      on_exit(fn ->
        Logger.configure(level: orig_level)
      end)

      :ok
    end

    test "it keeps the percentage at 1.0 if the observed dwell time is below the max" do
      check all max_dwell_time <- integer(1..5000),
                observed_dwell_time <- integer(0..max_dwell_time) do
        assert 1.0 ==
                 Congestion.calculate_emit_percentage(1.0, max_dwell_time, observed_dwell_time)
      end
    end

    test "it reduces the percentage if the observed dwell time is above the max" do
      check all max_dwell_time <- integer(1..5000),
                observed_dwell_time_millis <- integer(max_dwell_time..10_000) do
        observed_dwell_time_micros = observed_dwell_time_millis * 1000

        assert 0.5 ==
                 Congestion.calculate_emit_percentage(
                   1.0,
                   max_dwell_time,
                   observed_dwell_time_micros
                 )
      end
    end

    test "it raises the percentage if the observed dwell time is less than the max" do
      check all initial_emit_percentage <- float(min: 0.001, max: 0.9),
                max_dwell_time <- integer(1..5000),
                observed_dwell_time <- integer(0..max_dwell_time) do
        assert Congestion.calculate_emit_percentage(
                 initial_emit_percentage,
                 max_dwell_time,
                 observed_dwell_time
               ) > initial_emit_percentage
      end
    end

    test "it maintains a floor on the emit percentage" do
      Enum.reduce(1..1000, 0.001, fn _n, emit_percent ->
        new_emit_percentage = Congestion.calculate_emit_percentage(emit_percent, 1, 1001)
        assert new_emit_percentage == 0.001
        new_emit_percentage
      end)
    end

    test "the emit percentage cannot go above 1." do
      assert Congestion.calculate_emit_percentage(1.0, 10, 0) == 1.0
    end
  end

  describe "logging" do
    setup do
      orig_level = Logger.level()
      Logger.configure(level: :info)

      on_exit(fn ->
        Logger.configure(level: orig_level)
      end)

      :ok
    end

    test "logs are emitted when the emit percentage decreases" do
      log =
        capture_log(fn ->
          Congestion.calculate_emit_percentage(1.0, 1000, 1500)
        end)

      assert log =~ "[critical] Dwell time for emitter"
      assert log =~ "of 1500us exceeds 1000us. Now sampling at 50%"
    end

    test "logs are emitted when the emit percentage increases" do
      log =
        capture_log(fn ->
          Congestion.calculate_emit_percentage(0.9, 10, 8)
        end)

      assert log =~ "[info] Emitter #PID<"
      assert log =~ "raising emit percentage to 91.0%"
    end
  end

  describe "metrics" do
    test "the emit percentage is sent when it stays the same" do
      patch(:telemetry, :execute, :ok)

      Congestion.calculate_emit_percentage(1.0, 500, 3)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage],
          %{value: 100}
        )
      )
    end

    test "the emit percentage is sent when it stays the decreases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        Congestion.calculate_emit_percentage(1.0, 500, 600)
      end)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage],
          %{value: 50}
        )
      )
    end

    test "the emit percentage is sent when it stays the increases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        Congestion.calculate_emit_percentage(0.5, 500, 10)
      end)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage],
          %{value: 51}
        )
      )
    end

    test "dwell time is sent when it stays the same" do
      patch(:telemetry, :execute, :ok)

      Congestion.calculate_emit_percentage(1.0, 500, 3)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :dwell_time],
          %{duration: 3}
        )
      )
    end

    test "dwell time is sent when it stays the decreases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        Congestion.calculate_emit_percentage(1.0, 500, 600)
      end)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :dwell_time],
          %{duration: 600}
        )
      )
    end

    test "dwell time is sent when it stays the increases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        Congestion.calculate_emit_percentage(0.5, 500, 10)
      end)

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :dwell_time],
          %{duration: 10}
        )
      )
    end

    test "no delta metrics are emitted when the emit percentage stays the same" do
      patch(:telemetry, :execute, :ok)

      1.0 = Congestion.calculate_emit_percentage(1.0, 500, 3)

      refute_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :increase],
          %{value: 1.0}
        )
      )
    end

    test "delta metrics are emitted when the emit percentage decreases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        0.5 = Congestion.calculate_emit_percentage(1.0, 500, 501)
      end)

      refute_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :increase],
          %{count: 1}
        )
      )

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :decrease],
          %{count: 1}
        )
      )
    end

    test "delta metrics are emitted when the emit percentage increases" do
      patch(:telemetry, :execute, :ok)

      capture_log(fn ->
        0.51 = Congestion.calculate_emit_percentage(0.5, 500, 499)
      end)

      refute_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :decrease],
          %{count: 1}
        )
      )

      assert_called(
        :telemetry.execute(
          [:telemetry_metrics_statsd, :congestion, :emit_percentage, :increase],
          %{count: 1}
        )
      )
    end
  end
end
