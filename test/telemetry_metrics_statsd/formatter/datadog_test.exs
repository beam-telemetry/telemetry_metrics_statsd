defmodule TelemetryMetricsStatsd.Formatter.DatadogTest do
  use ExUnit.Case, async: true

  import TelemetryMetricsStatsd.Test.Helpers

  alias TelemetryMetricsStatsd.Formatter.Datadog

  test "counter update is formatted as a Datadog counter with 1 as a value" do
    m = given_counter("my.awesome.metric")

    assert format(m, 30, []) == "my.awesome.metric:1|c"
  end

  test "positive sum update is formatted as a Datadog counter with n value" do
    m = given_sum("my.awesome.metric")

    assert format(m, 21, []) == "my.awesome.metric:21|c"
  end

  test "negative sum update is formatted as a Datadog counter with -n value" do
    m = given_sum("my.awesome.metric")

    assert format(m, -21, []) == "my.awesome.metric:-21|c"
  end

  test "last_value update is formatted as a Datadog gauge with absolute value" do
    m = given_last_value("my.awesome.metric")

    assert format(m, -18, []) == "my.awesome.metric:-18|g"
  end

  test "summary update is formatted as a Datadog histogram" do
    m = given_summary("my.awesome.metric")

    assert format(m, 121, []) == "my.awesome.metric:121|h"
  end

  test "distribution update is formatted as a Datadog histogram" do
    m = given_distribution("my.awesome.metric")

    assert format(m, 131, []) == "my.awesome.metric:131|d"
  end

  test "StatsD metric name is based on metric name and tags" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: "GET", status: 200) ==
             "my.awesome.metric:131|g|#method:GET,status:200"
  end

  test "nil tags are included in the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: nil, status: 200) ==
             "my.awesome.metric:131|g|#method:nil,status:200"
  end

  test "empty tag values are included in the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:method, :status])

    assert format(m, 131, method: "", status: 200) ==
             "my.awesome.metric:131|g|#method:,status:200"
  end

  test "tags passed as explicit argument are used for the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:whatever])

    assert format(m, 131, method: "GET", status: 200) ==
             "my.awesome.metric:131|g|#method:GET,status:200"
  end

  test "float measurements are allowed" do
    m = given_last_value("my.awesome.metric")

    assert format(m, 131.4, []) ==
             "my.awesome.metric:131.4|g"

    assert format(m, 131.5, []) ==
             "my.awesome.metric:131.5|g"
  end

  test "sampling rate is added to third field" do
    m = given_last_value("my.awesome.metric", reporter_options: [sampling_rate: 0.2])

    assert format(m, 131.4, []) == "my.awesome.metric:131.4|g|@0.2"
  end

  test "sampling rate is ignored if == 1.0" do
    m = given_last_value("my.awesome.metric", reporter_options: [sampling_rate: 1.0])

    assert format(m, 131.4, []) == "my.awesome.metric:131.4|g"
  end

  test "tag values passed as list are included in the formatted metric as multiple tags" do
    m = given_last_value("my.awesome.metric", tags: [:method, :item, :status])

    assert format(m, 131, method: "GET", item: ["a", "b", "c"], status: 200) ==
             "my.awesome.metric:131|g|#method:GET,item:a,item:b,item:c,status:200"
  end

  test "tag values passed as list with one item are included in the formatted metric" do
    m = given_last_value("my.awesome.metric", tags: [:method, :item, :status])

    assert format(m, 131, method: "GET", item: ["a"], status: 200) ==
             "my.awesome.metric:131|g|#method:GET,item:a,status:200"
  end

  test "tag values passed as list are included in the formatted metric as multiple tags, when missing tag values" do
    m = given_last_value("my.awesome.metric", tags: [:method, :item, :status])

    assert format(m, 131, item: ["a", "b", "c"], status: 200) ==
             "my.awesome.metric:131|g|#item:a,item:b,item:c,status:200"
  end

  test "tag values passed as list with one item are included in the formatted metric, when missing tag values" do
    m = given_last_value("my.awesome.metric", tags: [:method, :item, :status])

    assert format(m, 131, item: ["a"], status: 200) ==
             "my.awesome.metric:131|g|#item:a,status:200"
  end

  defp format(metric, value, tags) do
    Datadog.format(metric, value, tags)
    |> :erlang.iolist_to_binary()
  end
end
