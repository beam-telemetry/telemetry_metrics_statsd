defmodule TelemetryMetricsStatsd.Formatter do
  @moduledoc false

  @type t :: module()

  @callback format(
              Telemetry.Metrics.t(),
              measurement :: number(),
              tags :: [
                {Telemetry.Metrics.tag(), term()}
              ]
            ) :: iodata()

  @spec format(
          t(),
          Telemetry.Metrics.t(),
          TelemetryMetricsStatsd.prefix(),
          measurement :: number(),
          tags :: [
            {Telemetry.Metrics.tag(), term()}
          ]
        ) :: binary()
  def format(formatter, metric, nil, measurement, tags) do
    formatter.format(metric, measurement, tags)
    |> :erlang.iolist_to_binary()
  end

  def format(formatter, metric, prefix, measurement, tags) do
    [prefix, ?., formatter.format(metric, measurement, tags)]
    |> :erlang.iolist_to_binary()
  end
end
