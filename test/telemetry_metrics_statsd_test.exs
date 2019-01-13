defmodule TelemetryMetricsStatsdTest do
  use ExUnit.Case, async: true

  test "counter metric is reported as StatsD counter with 1 as a value" do
    {socket, port} = given_udp_port_opened()
    counter = given_counter([:http, :request], name: [:http, :requests])

    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], 172)
    :telemetry.execute([:http, :request], 200)
    :telemetry.execute([:http, :request], 198)

    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.requests:1|c")
  end

  test "sum metric is reported as StatsD gauge with +n value" do
    {socket, port} = given_udp_port_opened()
    sum = given_sum([:payload, :received], name: [:payload, :received, :size])

    start_reporter(metrics: [sum], port: port)

    :telemetry.execute([:payload, :received], 2001)
    :telemetry.execute([:payload, :received], 1585)
    :telemetry.execute([:payload, :received], 1872)

    assert_reported(socket, "payload.received.size:+2001|g")
    assert_reported(socket, "payload.received.size:+1585|g")
    assert_reported(socket, "payload.received.size:+1872|g")
  end

  test "last value metric is reported as StatsD gauge with absolute value" do
    {socket, port} = given_udp_port_opened()
    last_value = given_last_value([:vm, :total_memory])

    start_reporter(metrics: [last_value], port: port)

    :telemetry.execute([:vm, :total_memory], 2001)
    :telemetry.execute([:vm, :total_memory], 1585)
    :telemetry.execute([:vm, :total_memory], 1872)

    assert_reported(socket, "vm.total_memory:2001|g")
    assert_reported(socket, "vm.total_memory:1585|g")
    assert_reported(socket, "vm.total_memory:1872|g")
  end

  test "distribution metric is reported as StastD timer" do
    {socket, port} = given_udp_port_opened()

    dist =
      given_distribution([:http, :request],
        name: [:http, :response_time],
        buckets: [0, 100, 200, 300]
      )

    start_reporter(metrics: [dist], port: port)

    :telemetry.execute([:http, :request], 172)
    :telemetry.execute([:http, :request], 200)
    :telemetry.execute([:http, :request], 198)

    assert_reported(socket, "http.response_time:172|t")
    assert_reported(socket, "http.response_time:200|t")
    assert_reported(socket, "http.response_time:198|t")
  end

  test "StatsD metric name is based on metric name and tags" do
    {socket, port} = given_udp_port_opened()

    counter =
      given_counter([:http, :request],
        name: [:http, :requests],
        metadata: :all,
        tags: [:method, :status]
      )

    start_reporter(metrics: [counter], port: port)

    :telemetry.execute([:http, :request], 172, %{method: "GET", status: 200})
    :telemetry.execute([:http, :request], 200, %{method: "POST", status: 201})
    :telemetry.execute([:http, :request], 198, %{method: "GET", status: 404})

    assert_reported(socket, "http.requests.GET.200:1|c")
    assert_reported(socket, "http.requests.POST.201:1|c")
    assert_reported(socket, "http.requests.GET.404:1|c")
  end

  test "multiple metrics can be tracked at the same time" do
    {socket, port} = given_udp_port_opened()
    counter = given_counter([:http, :request], name: [:http, :requests])

    dist =
      given_distribution([:http, :request],
        name: [:http, :response_time],
        buckets: [0, 100, 200, 300]
      )

    start_reporter(metrics: [counter, dist], port: port)

    :telemetry.execute([:http, :request], 172)
    :telemetry.execute([:http, :request], 200)
    :telemetry.execute([:http, :request], 198)

    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.response_time:172|t")
    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.response_time:200|t")
    assert_reported(socket, "http.requests:1|c")
    assert_reported(socket, "http.response_time:198|t")
  end

  defp given_udp_port_opened() do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    {socket, port}
  end

  defp given_counter(event_name, opts \\ []) do
    Telemetry.Metrics.counter(event_name, opts)
  end

  defp given_sum(event_name, opts \\ []) do
    Telemetry.Metrics.sum(event_name, opts)
  end

  defp given_last_value(event_name, opts \\ []) do
    Telemetry.Metrics.last_value(event_name, opts)
  end

  defp given_distribution(event_name, opts \\ []) do
    Telemetry.Metrics.distribution(event_name, opts)
  end

  defp start_reporter(options) do
    start_supervised!({TelemetryMetricsStatsd, options})
  end

  defp assert_reported(socket, expected_payload) do
    expected_size = byte_size(expected_payload)
    {:ok, {_host, _port, payload}} = :gen_udp.recv(socket, expected_size)
    assert payload == expected_payload
  end
end
