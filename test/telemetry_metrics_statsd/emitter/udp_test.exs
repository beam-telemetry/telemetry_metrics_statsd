defmodule TelemetryMetricsStatsd.Emitter.UdpTest do
  alias TelemetryMetricsStatsd.Emitter

  use ExUnit.Case
  use ExUnitProperties
  use Patch

  import ExUnit.CaptureLog
  import Liveness
  import Record
  import TelemetryMetricsStatsd.Test.Helpers

  defrecordp :hostent, extract(:hostent, from_lib: "kernel/include/inet.hrl")

  @metric "metric1:1|c"

  def new_emitter(options \\ []) do
    name = Keyword.get(options, :name, Emitter)

    defaults = [host: "127.0.0.1", port: 8893, name: name, emitters: 1, metrics: []]

    new_emitter(Emitter.UDP, defaults, options)
  end

  defp patch_socket_init do
    patch(:socket, :open, {:ok, :socket})
    patch(:socket, :connect, :ok)
  end

  describe "start_link/1" do
    test "opens an inet socket by default" do
      patch_socket_init()

      {:ok, _} = new_emitter()

      assert_called :socket.open(:inet, :dgram, :udp)
      assert_called :socket.connect(_, %{port: _, addr: {127, 0, 0, 1}, family: :inet})
    end

    test "can open an ipv6 socket" do
      patch_socket_init()

      {:ok, _} = new_emitter(host: "::1", inet_address_family: :inet6)

      assert_called :socket.open(:inet6, :dgram, :udp)
      assert_called :socket.connect(_, %{port: _, addr: {0, 0, 0, 0, 0, 0, 0, 1}, family: :inet6})
    end
  end

  describe "emitting metrics" do
    test "metrics are sent immediately if the mtu is 0" do
      patch(:socket, :send, :ok)

      {:ok, emitter} = new_emitter(mtu: 0)

      emit(emitter, @metric)

      assert_called :socket.send(_, @metric)
    end

    test "buffers data if under the mtu" do
      patch(:socket, :send, :ok)

      {:ok, emitter} = new_emitter(mtu: byte_size(@metric) + 1)

      emit(emitter, @metric)

      refute_any_call :socket.send()
    end

    test "emits data over the mtu" do
      patch(:socket, :send, :ok)

      {:ok, emitter} = new_emitter(mtu: byte_size(@metric) - 1)
      emit(emitter, @metric)

      assert_called :socket.send(_, @metric)
    end

    test "emits all metrics if the old data is below the mtu and the new data is above the mtu" do
      patch(:socket, :send, :ok)

      over_mtu_metric = "metric1:11|c"

      {:ok, emitter} = new_emitter(mtu: byte_size(over_mtu_metric), flush_timeout: 10)
      emit(emitter, @metric)

      refute_any_call :socket.send()

      emit(emitter, over_mtu_metric)

      assert_called :socket.send(_, [@metric])
      assert_called :socket.send(_, ^over_mtu_metric)
    end

    test "sends data after a timeout" do
      patch(:socket, :send, :ok)

      {:ok, emitter} = new_emitter(flush_timeout: 10)
      emit(emitter, @metric)

      refute_any_call :socket.send()

      eventually(fn -> assert_called(:socket.send(_, [@metric])) end)
    end

    test "does not reset the flush timeout when it receives a resolution message" do
      patch(:socket, :send, :ok)

      refute_any_call :socket.send()

      {:ok, emitter} = new_emitter(flush_timeout: 50)
      emit(emitter, @metric)
      send(emitter, :resolve_host)

      {elapsed_us, _} =
        :timer.tc(fn ->
          refute_any_call :socket.send()

          rapid_eventually(fn -> assert_called :socket.send(_, [@metric]) end)
        end)

      assert elapsed_us in 48_000..60_000
    end

    defp rapid_eventually(fun) do
      eventually(fun, 100, 1)
    end

    test "does not reset the flush timeout after it receives a dwell time probe" do
      patch(:socket, :send, :ok)
      spy(Emitter.Congestion)
      refute_any_call :socket.send()

      {:ok, emitter} = new_emitter(flush_timeout: 50)

      emit(emitter, @metric)
      send(emitter, :check_dwell_time)

      {elapsed_us, _} =
        :timer.tc(fn ->
          rapid_eventually(fn ->
            assert_called(Emitter.Congestion.calculate_emit_percentage(_, _, _))
          end)

          refute_any_call :socket.send()

          rapid_eventually(fn -> assert_called :socket.send(_, [@metric]) end)
        end)

      assert elapsed_us in 45_000..60_000
    end

    test "exits on a udp error" do
      patch(:socket, :send, {:error, :einval})

      {:ok, emitter} = new_emitter(mtu: 0, flush_timeout: 50)

      capture_log(fn ->
        assert {:einval, _} = catch_exit(emit(emitter, @metric))
      end)
    end
  end

  describe "hostname resolution" do
    test "is performed on start by default" do
      patch_socket_init()
      patch(:socket, :send, :ok)

      {:ok, _emitter} = new_emitter(host: "localhost", flush_timeout: 0)

      eventually(fn -> assert_called :socket.connect(_, %{addr: {127, 0, 0, 1}}) end)
    end

    test "Supports IPv6" do
      patch_socket_init()

      {:ok, _emitter} = new_emitter(host: "::1", inet_address_family: :inet6, flush_timeout: 0)

      eventually(fn -> assert_called :socket.connect(_, %{addr: {0, 0, 0, 0, 0, 0, 0, 1}}) end)
    end

    test "is not periodically repeated by default" do
      patch(:gen_udp, :send, :ok)
      spy(Emitter.UDP)

      {:ok, _} = new_emitter(host: "localhost")

      refute_called Emitter.UDP.handle_info(:resolve_host, _)
    end

    test "crashes on startup when it fails" do
      patch(:inet, :gethostbyname, {:error, :nxdomain})

      assert {:error, :nxdomain} = new_emitter(host: "localhost", supervised?: false)
    end

    test "handles failures on the resolution interval gracefully" do
      patch_socket_init()
      patch(:socket, :send, :ok)
      spy(Emitter.UDP)

      host_entry = hostent(h_addr_list: [{127, 0, 0, 1}])

      # The startup resolution call should succeed,
      # and the subsequent :resolve_host call should fail.
      patch(
        :inet,
        :gethostbyname,
        cycle([{:ok, host_entry}, {:error, :nxdomain}])
      )

      {:ok, emitter} =
        new_emitter(host: "localhost", host_resolution_interval: 100, flush_timeout: 10)

      send(emitter, :resolve_host)
      emit(emitter, @metric)

      eventually(fn -> assert_called(Emitter.UDP.handle_info(:resolve_host, _)) end)
      eventually(fn -> assert_called :socket.send(_, [@metric]) end)

      # we should only connect once at the beginning if resolution failed.
      assert_called :socket.connect(:socket, %{port: _, addr: {127, 0, 0, 1}, family: :inet}), 1
    end

    test "is periodically repeated if configured" do
      patch(:gen_udp, :send, :ok)
      spy(Emitter.UDP)

      {:ok, _} = new_emitter(host: "localhost", host_resolution_interval: 100)

      eventually(fn -> assert_called Emitter.UDP.handle_info(:resolve_host, _), 2 end)
    end

    test "does not interfere with flush timeouts" do
      me = self()

      patch(:socket, :send, fn _, data ->
        send(me, {:sent_at, data, System.system_time(:millisecond)})
        :ok
      end)

      {:ok, emitter} = new_emitter(host_resolution_interval: 500, flush_timeout: 100)
      emit(emitter, @metric)

      post_emit = System.system_time(:millisecond)

      send(emitter, :resolve_host)

      assert_receive {:sent_at, [@metric], written_at}, 200
      elapsed = written_at - post_emit
      assert elapsed in 100..105
    end
  end

  describe "congestion control" do
    setup do
      with_logger_level(:none)
      :ok
    end

    def emit_percentage(emitter) do
      :sys.get_state(emitter).emit_percentage
    end

    def send_dwell_time_probe(emitter, expected_dwell_time_millis \\ 0) do
      expeceted_dwell_time_micros = expected_dwell_time_millis * 1000
      start_time = System.system_time(:microsecond) - expeceted_dwell_time_micros

      send(emitter, {:probe_dwell_time, start_time})
    end

    test "keeps the percentage at 1.0 if there is no message queue" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 150)

      Enum.each(1..10, fn _ -> send_dwell_time_probe(emitter) end)

      assert emit_percentage(emitter) == 1.0
    end

    test "reduces the percentage if there is no message queue" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      send_dwell_time_probe(emitter, 150)

      assert eventually(fn -> emit_percentage(emitter) == 0.5 end)
    end

    test "logs a critical message when the percentage drops" do
      Logger.configure(level: :debug)

      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      log =
        capture_log(fn ->
          eventually(fn ->
            send_dwell_time_probe(emitter, 150)
            assert emit_percentage(emitter) < 1.0
          end)
        end)

      assert log =~ "[critical] Dwell time for emitter"
      assert log =~ "Now sampling at 50%"
    end

    test "logs an info message when the percentage rises" do
      Logger.configure(level: :debug)

      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      capture_log(fn ->
        eventually(fn ->
          send_dwell_time_probe(emitter, 150)
          assert emit_percentage(emitter) < 1.0
        end)
      end)

      log =
        capture_log(fn ->
          eventually(fn ->
            send_dwell_time_probe(emitter)
            assert emit_percentage(emitter) > 0.5
          end)
        end)

      assert log =~ "[info] Emitter"
      assert log =~ "raising emit percentage to 51.0%"
    end

    test "the percentage never gets to zero" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.each(1..1000, fn _ -> send_dwell_time_probe(emitter, 150) end)

      assert eventually(fn ->
               {:message_queue_len, 0} = Process.info(emitter, :message_queue_len)
             end)

      assert emit_percentage(emitter) > 0.0
    end

    test "the percentage increases when the dwell time drops below the max" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      send_dwell_time_probe(emitter, 150)

      eventually(fn -> assert emit_percentage(emitter) < 1.0 end)

      old_percentage = emit_percentage(emitter)

      send_dwell_time_probe(emitter)

      assert eventually(fn -> emit_percentage(emitter) > old_percentage end)
    end

    test "the percentage will eventually recover" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      send_dwell_time_probe(emitter, 150)

      Enum.map(1..50, fn _ -> send_dwell_time_probe(emitter) end)

      assert eventually(fn -> emit_percentage(emitter) == 1.0 end)
    end

    test "the percentage will never go over 1.0" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 5)

      Enum.map(1..200, fn _ -> send_dwell_time_probe(emitter) end)

      assert eventually(fn ->
               {:message_queue_len, 0} = Process.info(emitter, :message_queue_len)
             end)

      assert emit_percentage(emitter) == 1.0
    end

    test "the percentage will never go below 0.001" do
      {:ok, emitter} = new_emitter(max_queue_dwell_time: 100)

      Enum.map(1..500, fn _ -> send_dwell_time_probe(emitter, 150) end)

      assert eventually(fn ->
               {:message_queue_len, 0} = Process.info(emitter, :message_queue_len)
             end)

      assert emit_percentage(emitter) >= 0.001
    end
  end

  defp with_logger_level(level) do
    old_level = Logger.level()
    Logger.configure(level: level)

    on_exit(fn ->
      Logger.configure(level: old_level)
    end)
  end

  # min metric is size 5: n:1|c
  @min_metric_size 5

  def new_emitter!(opts \\ []) do
    case new_emitter(opts) do
      {:ok, emitter} ->
        emitter

      {:error, {:already_started, emitter}} ->
        Supervisor.stop(emitter, :normal)
        new_emitter!(opts)
    end
  end

  def concat(iodata, "") do
    iodata
  end

  def concat([], metric) do
    [metric]
  end

  def concat(iodata, metric) do
    [iodata, "\n", metric]
  end

  @tag timeout: :infinity
  property "emits packets whose size under the MTU" do
    test = self()

    patch(:socket, :send, fn _, data ->
      send(test, {:emitted, data})
      :ok
    end)

    check all mtu <- integer(1..4096),
              metrics <-
                list_of(
                  string([?a..?z, ?:..?:, ?|..?|], min_length: @min_metric_size, max_length: mtu),
                  max_length: 400
                ) do
      emitter = new_emitter!(mtu: mtu, supervised?: false, flush_timeout: 10)

      metrics
      |> Enum.chunk_every(2, 1, [""])
      |> Enum.reduce([], fn
        [current_metric, next_metric], metrics ->
          metric_iodata = Enum.intersperse(metrics, "\n")
          new_metric = concat(metric_iodata, current_metric)
          next_metric = concat(new_metric, next_metric)

          if IO.iodata_length(new_metric) < mtu and IO.iodata_length(next_metric) >= mtu do
            Enum.each(metrics ++ [current_metric], &emit(emitter, &1))

            assert_receive({:emitted, packet})
            packet_binary = IO.iodata_to_binary(packet)
            assert packet_binary == IO.iodata_to_binary(new_metric)
            []
          else
            metrics ++ [current_metric]
          end
      end)
    end
  end
end
