defmodule TelemetryMetricsStatsd.FormatterTest do
  use ExUnit.Case

  import TelemetryMetricsStatsd.Test.Helpers

  alias TelemetryMetricsStatsd.Formatter
  alias Formatter.{Standard, Datadog}

  test "formats the measurement using provided formatter implementation with prefix" do
    metric = given_counter("http.duration", tags: [:resource, :method])

    assert Formatter.format(Standard, metric, "api", 1, resource: "users", method: "GET") ==
             "api.http.duration.users.GET:1|c"

    assert Formatter.format(Datadog, metric, "api", 1, resource: "users", method: "GET") ==
             "api.http.duration:1|c#resource:users,method:GET"
  end

  test "formats the measurement using provided formatter implementation without prefix" do
    metric = given_counter("http.duration", tags: [:resource, :method])

    assert Formatter.format(Standard, metric, nil, 1, resource: "users", method: "GET") ==
             "http.duration.users.GET:1|c"

    assert Formatter.format(Datadog, metric, nil, 1, resource: "users", method: "GET") ==
             "http.duration:1|c#resource:users,method:GET"
  end
end
