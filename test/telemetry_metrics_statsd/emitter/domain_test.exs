defmodule TelemetryMetricsStatsd.Emitter.DomainTest do
  alias TelemetryMetricsStatsd.Emitter

  use ExUnit.Case
  use ExUnitProperties
  use Patch

  import ExUnit.CaptureLog
  import Liveness
  import Record
  import TelemetryMetricsStatsd.Test.Helpers

  defrecordp :hostent, extract(:hostent, from_lib: "kernel/include/inet.hrl")

  @socket_path "/tmp/metrics.sock"
  @metric "metric1:1|c"

  setup do
    patch(:socket, :open, {:ok, :socket})
    patch(:socket, :connect, :ok)
    patch(:socket, :send, :ok)
    :ok
  end

  def new_emitter(options \\ []) do
    name = Keyword.get(options, :name, Emitter)

    defaults = [
      socket_path: @socket_path,
      name: name,
      emitters: 1,
      metrics: [],
      dwell_time_check_interval: 50
    ]

    new_emitter(Emitter.Domain, defaults, options)
  end

  describe "start_link/1" do
    test "opens an local socket by default" do
      {:ok, _} = new_emitter()

      assert_called :socket.open(:local, :dgram)
      assert_called :socket.connect(:socket, %{family: :local, path: @socket_path})
    end
  end

  describe "emitting metrics" do
    test "metrics are sent immediately" do
      patch(:socket, :send, :ok)

      {:ok, emitter} = new_emitter(mtu: 0)

      emit(emitter, @metric)

      assert_called :socket.send(_, @metric)
    end

    test "exits on a socket error" do
      capture_log(fn ->
        patch(:socket, :send, {:error, :einval})

        {:ok, emitter} = new_emitter(mtu: 0)
        ref = Process.monitor(emitter)

        assert :ok = emit(emitter, @metric)
        assert_receive {:DOWN, ^ref, :process, ^emitter, :einval}
      end)
    end
  end

  describe "congestion control" do
    setup do
      Logger.configure(level: :none)
      :ok
    end

    def emit_percentage(emitter) do
      :sys.get_state(emitter).emit_percentage
    end

    def send_dwell_time_probe(emitter, expected_dwell_time_millis \\ 0) do
      expected_dwell_time_micros = expected_dwell_time_millis * 1000
      now = System.system_time(:microsecond)
      start_time = now - expected_dwell_time_micros

      send(emitter, {:probe_dwell_time, start_time})
    end

    def wait_for_empty_queue(emitter) do
      eventually(fn -> {:message_queue_len, 0} = Process.info(emitter, :message_queue_len) end)
    end

    test "keeps the percentage at 1.0 if there is no latency" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.each(1..10, fn _ -> emit(emitter, @metric) end)

      assert emit_percentage(emitter) == 1.0
    end

    test "keeps the percentage at 1.0 if the dwell time is under the limit" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.each(1..10, fn _ -> send_dwell_time_probe(emitter, 99) end)

      assert emit_percentage(emitter) == 1.0
    end

    test "reduces the percentage if the dwell time is over the limit" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 150)

      send_dwell_time_probe(emitter, 150)

      eventually(fn -> assert emit_percentage(emitter) == 0.5 end)
    end

    test "logs a critical message when the percentage drops" do
      Logger.configure(level: :debug)

      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      log =
        capture_log(fn ->
          send_dwell_time_probe(emitter, 150)

          eventually(fn ->
            :sys.get_state(emitter).emit_percentage < 1.0
          end)
        end)

      assert log =~ "[critical] Dwell time for emitter"
      assert log =~ "Now sampling at 50.0%"
    end

    test "logs an info message when the percentage rises" do
      Logger.configure(level: :debug)

      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      capture_log(fn ->
        eventually(fn ->
          send_dwell_time_probe(emitter, 150)
          :sys.get_state(emitter).emit_percentage < 1.0
        end)
      end)

      restore(Emitter.Domain, :dwell_time)

      log =
        capture_log(fn ->
          eventually(fn ->
            send_dwell_time_probe(emitter)
            :sys.get_state(emitter).emit_percentage == 1.0
          end)
        end)

      assert log =~ "[info] Emitter"
      assert log =~ "raising emit percentage to 51.0%"
    end

    test "the percentage never gets to zero" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.each(1..100, fn _ ->
        send_dwell_time_probe(emitter, 150)
      end)

      wait_for_empty_queue(emitter)

      assert emit_percentage(emitter) > 0.0
    end

    test "the percentage increases when the dwell time drops below max dwell time" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      send_dwell_time_probe(emitter, 150)

      eventually(fn ->
        emit_percentage(emitter) < 1.0
      end)

      old_percentage = emit_percentage(emitter)

      send_dwell_time_probe(emitter)

      assert eventually(fn -> emit_percentage(emitter) > old_percentage end)
    end

    test "the percentage will eventually recover" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      eventually(fn ->
        send_dwell_time_probe(emitter, 150)
        assert emit_percentage(emitter) < 10
      end)

      assert eventually(fn ->
               send_dwell_time_probe(emitter)
               emit_percentage(emitter) == 1.0
             end)
    end

    test "the percentage will never go over 1.0" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 5)

      eventually(fn ->
        send_dwell_time_probe(emitter)
        assert emit_percentage(emitter) == 1.0
      end)
    end

    test "the percentage will never go below 0.001" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.map(1..100, fn _ -> send_dwell_time_probe(emitter, 150) end)

      wait_for_empty_queue(emitter)

      assert emit_percentage(emitter) >= 0.001
    end
  end
end
