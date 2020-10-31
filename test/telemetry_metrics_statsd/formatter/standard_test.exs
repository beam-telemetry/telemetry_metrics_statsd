defmodule TelemetryMetricsStatsd.Formatter.StandardTest do
  use ExUnit.Case, async: true

  import TelemetryMetricsStatsd.Test.Helpers

  alias TelemetryMetricsStatsd.Formatter.Standard

  test "counter update is formatted as a StatsD counter with 1 as a value" do
    m = given_counter("my.awesome.metric")

    assert format(m, 30, []) == "my.awesome.metric:1|c"
  end

  test "positive sum update is formatted as a StatsD gauge with +n value" do
    m = given_sum("my.awesome.metric")

    assert format(m, 21, []) == "my.awesome.metric:+21|g"
  end

  test "negative sum update is formatted as a StatsD gauge with -n value" do
    m = given_sum("my.awesome.metric")

    assert format(m, -21, []) == "my.awesome.metric:-21|g"
  end

  test "positive sum as counter update is formatted as a StatsD counter with n value" do
    m = given_sum("my.awesome.metric", reporter_options: [report_as: :counter])

    assert format(m, 21, []) == "my.awesome.metric:21|c"
  end

  @tag capture_log: true
  test "negative sum as counter update is dropped" do
    m = given_sum("my.awesome.metric", reporter_options: [report_as: :counter])

    assert format(m, -21, []) == ""
  end

  test "last_value update is formatted as a StatsD gauge with absolute value" do
    m = given_last_value("my.awesome.metric")

    assert format(m, -18, []) == "my.awesome.metric:-18|g"
  end

  test "summary update is formatted as a StatsD timer" do
    m = given_summary("my.awesome.metric")

    assert format(m, 121, []) == "my.awesome.metric:121|ms"
  end

  test "distribution update is formatted as a StatsD timer" do
    m = given_distribution("my.awesome.metric")

    assert format(m, 131, []) == "my.awesome.metric:131|ms"
  end

  test "StatsD metric name is based on metric name and tags" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: "GET", status: 200) ==
             "my.awesome.metric.GET.200:131|g"
  end

  test "nil tags are included in the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: nil, status: 200) ==
             "my.awesome.metric.nil.200:131|g"
  end

  test "empty string tag values are dropped" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: "", status: 200) == ""
  end

  test "tags passed as explicit argument are used for the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:whatever])

    assert format(m, 131, method: "GET", status: 200) ==
             "my.awesome.metric.GET.200:131|g"
  end

  test "float measurements are rounded to integers" do
    m = given_last_value("my.awesome.metric")

    assert format(m, 131.4, []) ==
             "my.awesome.metric:131|g"

    assert format(m, 131.5, []) ==
             "my.awesome.metric:132|g"
  end

  test "sampling rate is added to third field" do
    m = given_last_value("my.awesome.metric", reporter_options: [sampling_rate: 0.2])

    assert format(m, 131.4, []) == "my.awesome.metric:131|g|@0.2"
  end

  test "sampling rate is ignored if == 1.0" do
    m = given_last_value("my.awesome.metric", reporter_options: [sampling_rate: 1.0])

    assert format(m, 131.4, []) == "my.awesome.metric:131|g"
  end

  defp format(metric, value, tags) do
    Standard.format(metric, value, tags)
    |> :erlang.iolist_to_binary()
  end
end
