defmodule TelemetryMetricsStatsdTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import TelemetryMetricsStatsd.Test.Helpers
  import Liveness
  import Mock

  test "counter metric is reported as StatsD counter with 1 as a value" do
    {socket, port} = given_udp_port_opened()
    counter = given_counter("http.requests", event_name: "http.request")

    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], %{latency: 211})
    :telemetry.execute([:http, :request], %{latency: 200})
    :telemetry.execute([:http, :request], %{latency: 198})

    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.requests:1|c")
  end

  test "sum metric is reported as StatsD gauge with +n value" do
    {socket, port} = given_udp_port_opened()
    sum = given_sum("http.request.payload_size")

    start_reporter(metrics: [sum], port: port)

    :telemetry.execute([:http, :request], %{payload_size: 2001})
    :telemetry.execute([:http, :request], %{payload_size: 1585})
    :telemetry.execute([:http, :request], %{payload_size: 1872})

    assert_reported(socket, "http.request.payload_size:+2001|g")
    assert_reported(socket, "http.request.payload_size:+1585|g")
    assert_reported(socket, "http.request.payload_size:+1872|g")
  end

  test "last value metric is reported as StatsD gauge with absolute value" do
    {socket, port} = given_udp_port_opened()
    last_value = given_last_value("vm.memory.total")

    start_reporter(metrics: [last_value], port: port)

    :telemetry.execute([:vm, :memory], %{total: 2001})
    :telemetry.execute([:vm, :memory], %{total: 1585})
    :telemetry.execute([:vm, :memory], %{total: 1872})

    assert_reported(socket, "vm.memory.total:2001|g")
    assert_reported(socket, "vm.memory.total:1585|g")
    assert_reported(socket, "vm.memory.total:1872|g")
  end

  test "summary metric is reported as StatsD timer" do
    {socket, port} = given_udp_port_opened()
    summary = given_summary("http.request.latency")

    start_reporter(metrics: [summary], port: port)

    :telemetry.execute([:http, :request], %{latency: 172})
    :telemetry.execute([:http, :request], %{latency: 200})
    :telemetry.execute([:http, :request], %{latency: 198})

    assert_reported(socket, "http.request.latency:172|ms")
    assert_reported(socket, "http.request.latency:200|ms")
    assert_reported(socket, "http.request.latency:198|ms")
  end

  test "distribution metric is reported as StatsD timer" do
    {socket, port} = given_udp_port_opened()

    dist = given_distribution("http.request.latency")

    start_reporter(metrics: [dist], port: port)

    :telemetry.execute([:http, :request], %{latency: 172})
    :telemetry.execute([:http, :request], %{latency: 200})
    :telemetry.execute([:http, :request], %{latency: 198})

    assert_reported(socket, "http.request.latency:172|ms")
    assert_reported(socket, "http.request.latency:200|ms")
    assert_reported(socket, "http.request.latency:198|ms")
  end

  test "standard formatter can be provided explicitly" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter(
        "http.requests",
        event_name: "http.request",
        tags: [:env, :method, :status]
      )

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :standard,
      global_tags: [env: "prod"]
    )

    :telemetry.execute([:http, :request], %{latency: 172}, %{method: "GET", status: 200})
    :telemetry.execute([:http, :request], %{latency: 172}, %{method: "GET", status: 200})

    assert_reported(socket, "http.requests.prod.GET.200:1|c")
    assert_reported(socket, "http.requests.prod.GET.200:1|c")
  end

  test "DataDog formatter can be used" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter(
        "http.requests",
        event_name: "http.request",
        tags: [:env, :method, :status]
      )

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :datadog,
      global_tags: [env: "prod"]
    )

    :telemetry.execute([:http, :request], %{latency: 172}, %{method: "GET", status: 200})
    :telemetry.execute([:http, :request], %{latency: 200}, %{method: "POST", status: 201})
    :telemetry.execute([:http, :request], %{latency: 198}, %{method: "GET", status: 404})
    :telemetry.execute([:http, :request], %{latency: 198}, %{method: "GET", status: 404})

    assert_reported(socket, "http.requests:1|c|#env:prod,method:GET,status:200")
    assert_reported(socket, "http.requests:1|c|#env:prod,method:POST,status:201")
    assert_reported(socket, "http.requests:1|c|#env:prod,method:GET,status:404")
    assert_reported(socket, "http.requests:1|c|#env:prod,method:GET,status:404")
  end

  test "it fails to start with invalid formatter" do
    counter = given_counter("http.request.count")

    assert {:error, msg} =
             TelemetryMetricsStatsd.start_link(metrics: [counter], formatter: :my_formatter)

    assert msg ==
             "invalid value for :formatter option: expected :formatter be either :standard or :datadog, got :my_formatter"
  end

  test "it doesn't crash when tag values are missing" do
    {socket, port} = given_udp_port_opened()

    counter = given_counter("http.request.count", tags: [:method, :status])

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :datadog
    )

    handlers_before = :telemetry.list_handlers([])

    :telemetry.execute([:http, :request], %{latency: 172}, %{method: "GET"})
    assert_reported(socket, "http.request.count:1|c|#method:GET,status:")

    handlers_after = :telemetry.list_handlers([])
    assert handlers_after == handlers_before
  end

  test "measurement function is taken into account when getting the value for the metric" do
    {socket, port} = given_udp_port_opened()
    last_value = given_last_value("vm.memory.total", measurement: fn m -> m.total * 2 end)

    start_reporter(metrics: [last_value], port: port)

    :telemetry.execute([:vm, :memory], %{total: 2001})
    :telemetry.execute([:vm, :memory], %{total: 1585})
    :telemetry.execute([:vm, :memory], %{total: 1872})

    assert_reported(socket, "vm.memory.total:4002|g")
    assert_reported(socket, "vm.memory.total:3170|g")
    assert_reported(socket, "vm.memory.total:3744|g")
  end

  test "measurement function can take two arguments" do
    {socket, port} = given_udp_port_opened()

    last_value =
      given_last_value("my.statistics.mean",
        measurement: fn measurements, metadata -> measurements.sum / metadata.sample_size end
      )

    start_reporter(metrics: [last_value], port: port)

    :telemetry.execute([:my, :statistics], %{sum: 200}, %{sample_size: 2})
    :telemetry.execute([:my, :statistics], %{sum: 300}, %{sample_size: 3})
    :telemetry.execute([:my, :statistics], %{sum: 100}, %{sample_size: 1})

    assert_reported(socket, "my.statistics.mean:100|g")
    assert_reported(socket, "my.statistics.mean:100|g")
    assert_reported(socket, "my.statistics.mean:100|g")
  end

  test "there can be multiple metrics derived from the same event" do
    {socket, port} = given_udp_port_opened()

    dist = given_distribution("http.request.latency")

    sum = given_sum("http.request.payload_size")

    start_reporter(metrics: [dist, sum], port: port)

    :telemetry.execute([:http, :request], %{latency: 172, payload_size: 121})
    :telemetry.execute([:http, :request], %{latency: 200, payload_size: 64})
    :telemetry.execute([:http, :request], %{latency: 198, payload_size: 1021})

    assert_reported(
      socket,
      "http.request.latency:172|ms\n" <> "http.request.payload_size:+121|g"
    )

    assert_reported(
      socket,
      "http.request.latency:200|ms\n" <> "http.request.payload_size:+64|g"
    )

    assert_reported(
      socket,
      "http.request.latency:198|ms\n" <> "http.request.payload_size:+1021|g"
    )
  end

  test "too big payloads produced by single event are broken into multiple UDP datagrams" do
    {socket, port} = given_udp_port_opened()

    metrics = [
      given_counter("first.counter", event_name: "http.request"),
      given_counter("second.counter", event_name: "http.request"),
      given_counter("third.counter", event_name: "http.request"),
      given_counter("fourth.counter", event_name: "http.request")
    ]

    start_reporter(metrics: metrics, port: port, mtu: 40)

    :telemetry.execute([:http, :request], %{latency: 172, payload_size: 121})

    assert_reported(
      socket,
      "first.counter:1|c\n" <> "second.counter:1|c"
    )

    assert_reported(
      socket,
      "third.counter:1|c\n" <> "fourth.counter:1|c"
    )
  end

  test "global tags can be set" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter(
        "http.requests",
        event_name: "http.request",
        tags: [:env, :host, :method, :status]
      )

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :standard,
      global_tags: [env: "dev", host: "localhost"]
    )

    :telemetry.execute([:http, :request], %{latency: 172}, %{method: "GET", status: 200})

    assert_reported(socket, "http.requests.dev.localhost.GET.200:1|c")
  end

  test "event metadata overrides global tags with the same keys" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter(
        "http.requests",
        event_name: "http.request",
        tags: [:env, :host, :method, :status]
      )

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :standard,
      global_tags: [env: "dev", host: "localhost"]
    )

    :telemetry.execute([:http, :request], %{latency: 172}, %{
      method: "GET",
      status: 200,
      host: "example.com"
    })

    assert_reported(socket, "http.requests.dev.example.com.GET.200:1|c")
  end

  test "tags returned by :tag_values function override global tags with the same keys" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter(
        "http.requests",
        event_name: "http.request",
        tags: [:env, :host, :method, :status],
        tag_values: fn meta -> Map.put(meta, :host, "example.com") end
      )

    start_reporter(
      metrics: [counter],
      port: port,
      formatter: :standard,
      global_tags: [env: "dev", host: "localhost"]
    )

    :telemetry.execute([:http, :request], %{latency: 172}, %{
      method: "GET",
      status: 200
    })

    assert_reported(socket, "http.requests.dev.example.com.GET.200:1|c")
  end

  describe "UDP error handling" do
    test "reporting a UDP error logs an error" do
      reporter = start_reporter(metrics: [], pool_size: 1)
      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)

      assert capture_log(fn ->
               TelemetryMetricsStatsd.udp_error(reporter, udp, :closed)
               # errors.
               eventually(fn ->
                 {:ok, new_udp} = TelemetryMetricsStatsd.get_udp(pool_id)
                 new_udp != udp
               end)
             end) =~ ~r/\[error\] Failed to publish metrics over UDP: :closed/
    end

    test "reporting a UDP error for the same socket multiple times generates only one log" do
      reporter = start_reporter(metrics: [], pool_size: 1)
      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)

      assert capture_log(fn ->
               TelemetryMetricsStatsd.udp_error(reporter, udp, :closed)

               eventually(fn ->
                 {:ok, new_udp} = TelemetryMetricsStatsd.get_udp(pool_id)
                 new_udp != udp
               end)
             end) =~ ~r/\[error\] Failed to publish metrics over UDP: :closed/

      assert capture_log(fn ->
               TelemetryMetricsStatsd.udp_error(reporter, udp, :closed)

               eventually(fn ->
                 {:ok, new_udp} = TelemetryMetricsStatsd.get_udp(pool_id)
                 new_udp != udp
               end)
             end) == ""
    end

    @tag :capture_log
    test "reporting a UDP error and fetching a socket returns a new socket" do
      reporter = start_reporter(metrics: [], pool_size: 1)
      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)

      TelemetryMetricsStatsd.udp_error(reporter, udp, :closed)

      assert eventually(fn ->
               {:ok, new_udp} = TelemetryMetricsStatsd.get_udp(pool_id)
               new_udp != udp
             end)
    end

    @tag :capture_log
    test "reporting a UDP error and opening a new socket closes the old socket" do
      reporter = start_reporter(metrics: [], pool_size: 1)
      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)

      TelemetryMetricsStatsd.udp_error(reporter, udp, :closed)

      eventually(fn ->
        {:ok, new_udp} = TelemetryMetricsStatsd.get_udp(pool_id)
        new_udp != udp
      end)

      assert :gen_udp.recv(udp.socket, 0) == {:error, :closed}
    end
  end

  describe "Unix domain socket support" do
    test "reporter connects to a Unix domain socket" do
      {socket, socket_path} = given_unix_socket_opened()
      counter = given_counter("http.request.count")

      start_reporter(metrics: [counter], socket_path: socket_path)

      :telemetry.execute([:http, :request], %{latency: 213})

      assert_reported(socket, "http.request.count:1|c")
    end
  end

  test "published metrics are prefixed with the provided prefix" do
    {socket, port} = given_udp_port_opened()

    metrics = [
      given_counter("http.request.count"),
      given_distribution("http.request.latency"),
      given_last_value("http.request.current_memory"),
      given_sum("http.request.payload_size")
    ]

    start_reporter(metrics: metrics, port: port, prefix: "myapp")

    :telemetry.execute([:http, :request], %{latency: 200, current_memory: 200, payload_size: 200})

    assert_reported(
      socket,
      "myapp.http.request.count:1|c\n" <>
        "myapp.http.request.latency:200|ms\n" <>
        "myapp.http.request.current_memory:200|g\n" <> "myapp.http.request.payload_size:+200|g"
    )
  end

  @tag :capture_log
  test "metrics are not sent when reporter receives an exit signal" do
    {socket, port} = given_udp_port_opened()

    reporter =
      start_reporter(
        metrics: [
          given_counter("first.event.count"),
          given_counter("second.event.count")
        ],
        port: port
      )

    Process.unlink(reporter)

    # Make sure that event handlers are detached even if non-parent process sends an exit signal.
    spawn(fn -> Process.exit(reporter, :some_reason) end)
    eventually(fn -> not Process.alive?(reporter) end)

    assert :telemetry.list_handlers([:first, :event]) == []
    assert :telemetry.list_handlers([:second, :event]) == []

    :telemetry.execute([:first, :event], %{})
    :telemetry.execute([:second, :event], %{})

    refute_reported(socket)
  end

  test "metrics are not sent when reporter is shut down by its supervisor" do
    {socket, port} = given_udp_port_opened()

    metrics = [
      given_counter("first.event.count"),
      given_counter("second.event.count")
    ]

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {TelemetryMetricsStatsd, [metrics: metrics, port: port]}
        ],
        strategy: :one_for_one
      )

    Process.unlink(supervisor)

    Supervisor.stop(supervisor, :shutdown)

    assert :telemetry.list_handlers([:first, :event]) == []
    assert :telemetry.list_handlers([:second, :event]) == []

    :telemetry.execute([:first, :event], %{})
    :telemetry.execute([:second, :event], %{})

    refute_reported(socket)
  end

  test "non-number measurement prevents the metric from being updated" do
    {socket, port} = given_udp_port_opened()
    sum = given_sum("my.metric", event_name: [:my, :event], measurement: :non_number)

    start_reporter(metrics: [sum], port: port)

    :telemetry.execute([:my, :event], %{non_number: :not_a_number})

    refute_reported(socket)
  end

  test "doesn't report data for Counter metric when outside sample rate" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter("http.requests",
        event_name: "http.request",
        reporter_options: [sampling_rate: 0.1]
      )

    # :rand.uniform_real will return 0.3280001173553174
    :rand.seed(:exs1024, {1, 2, 2})

    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], %{sample: 42})

    refute_reported(socket)
  end

  test "doesn't report data when non-Counter metric outside sample rate" do
    {socket, port} = given_udp_port_opened()
    sum = given_sum("http.request.sample", reporter_options: [sampling_rate: 0.1])

    # :rand.uniform_real will return 0.3280001173553174
    :rand.seed(:exs1024, {1, 2, 2})

    start_reporter(metrics: [sum], port: port)

    :telemetry.execute([:http, :request], %{sample: 42})

    refute_reported(socket)
  end

  test "reports data for Counter metric when inside sample rate" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter("http.requests",
        event_name: "http.request",
        reporter_options: [sampling_rate: 0.1]
      )

    # :rand.uniform_real will return 0.06907625299228148
    :rand.seed(:exs1024, {1, 2, 3})

    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], %{sample: 42})

    assert_reported(socket, "http.requests:1|c|@0.1")
  end

  test "reports data when non-Counter metric inside sample rate" do
    {socket, port} = given_udp_port_opened()
    sum = given_sum("http.request.sample", reporter_options: [sampling_rate: 0.1])

    # :rand.uniform_real will return 0.06907625299228148
    :rand.seed(:exs1024, {1, 2, 3})

    start_reporter(metrics: [sum], port: port)

    :telemetry.execute([:http, :request], %{sample: 42})

    assert_reported(socket, "http.request.sample:+42|g|@0.1")
  end

  test "respects :keep and :drop options" do
    {socket, port} = given_udp_port_opened()
    counter = given_counter("http.request.count", keep: &match?(%{keep: true}, &1))
    summary = given_summary("http.request.duration", drop: &match?(%{drop: true}, &1))

    start_reporter(metrics: [counter, summary], port: port)

    :telemetry.execute([:http, :request], %{duration: 10}, %{keep: true})
    assert_reported(socket, "http.request.count:1|c\n" <> "http.request.duration:10|ms")

    :telemetry.execute([:http, :request], %{duration: 10}, %{keep: true, drop: true})
    assert_reported(socket, "http.request.count:1|c")

    :telemetry.execute([:http, :request], %{duration: 10}, %{drop: true})
    refute_reported(socket)
  end

  test "it supports a pool of sockets" do
    reporter = start_reporter(metrics: [], pool_size: 4)
    pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)

    udps =
      for _ <- 1..50, uniq: true do
        {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
        udp
      end

    assert length(udps) == 4
  end

  test "multiple reporters can be started" do
    {socket, port} = given_udp_port_opened()
    counter = given_counter("http.requests", event_name: "http.request")

    start_reporter(metrics: [counter], port: port)
    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], %{latency: 211})

    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.requests:1|c")
  end

  describe "hostname resolution" do
    test "is performed on start by default" do
      counter = given_counter("http.request.count")

      reporter =
        start_reporter(
          host: "localhost",
          metrics: [counter]
        )

      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)

      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
      assert udp.host == {127, 0, 0, 1}
    end

    test "is not periodically repeated by default" do
      counter = given_counter("http.request.count")

      reporter =
        start_reporter(
          host: "localhost",
          metrics: [counter]
        )

      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
      assert udp.host == {127, 0, 0, 1}

      with_mock :inet, [:passthrough, :unstick],
        gethostbyname: fn _ -> {:ok, {:hostent, 'localhost', [], :inet, 4, [{10, 0, 0, 0}]}} end do
        assert_raise Liveness, fn ->
          eventually(fn ->
            {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
            udp.host == {10, 0, 0, 0}
          end)
        end
      end
    end

    test "is periodically repeated if configured" do
      counter = given_counter("http.request.count")

      reporter =
        start_reporter(
          host: "localhost",
          metrics: [counter],
          host_resolution_interval: 100
        )

      pool_id = TelemetryMetricsStatsd.get_pool_id(reporter)
      {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
      assert udp.host == {127, 0, 0, 1}

      with_mock :inet, [:passthrough, :unstick],
        gethostbyname: fn _ -> {:ok, {:hostent, 'localhost', [], :inet, 4, [{10, 0, 0, 0}]}} end do
        eventually(fn ->
          {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
          assert udp.host == {10, 0, 0, 0}
        end)
      end

      eventually(fn ->
        {:ok, udp} = TelemetryMetricsStatsd.get_udp(pool_id)
        assert udp.host == {127, 0, 0, 1}
      end)
    end
  end

  defp given_udp_port_opened() do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    {socket, port}
  end

  defp given_unix_socket_opened() do
    socket_name = :crypto.strong_rand_bytes(50) |> Base.encode16(case: :lower)
    socket_path = Path.join("/tmp", socket_name)
    {:ok, socket} = :gen_udp.open(0, [:binary, :local, active: false, ip: {:local, socket_path}])
    {socket, socket_path}
  end

  defp start_reporter(options) do
    {:ok, pid} = TelemetryMetricsStatsd.start_link(options)
    pid
  end

  defp assert_reported(socket, expected_payload) do
    expected_size = byte_size(expected_payload)
    {:ok, {_host, _port, payload}} = :gen_udp.recv(socket, expected_size, 1000)
    assert payload == expected_payload
  end

  defp refute_reported(socket) do
    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 1000)
  end
end
