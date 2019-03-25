defmodule TelemetryMetricsStatsd.Formatter do
  @moduledoc false

  alias Telemetry.Metrics

  @spec format(
          prefix :: String.t | nil,
          Telemetry.Metrics.t(),
          :telemetry.event_value(),
          tags :: [
            {Telemetry.Metrics.tag(), term()}
          ]
        ) :: binary()
  def format(prefix, metric, value, tags) do
    [format_metric_name(prefix, metric.name, tags), ?:, format_metric_value(metric, value)]
    |> :erlang.iolist_to_binary()
  end

  defp format_metric_name(nil, metric_name, tags), do: format_metric_name(metric_name, tags)
  defp format_metric_name(prefix, metric_name, tags), do: format_metric_name([prefix | metric_name], tags)

  defp format_metric_name(metric_name, tags) do
    segments = metric_name ++ Enum.map(tags, fn {_, tag_value} -> tag_value end)

    segments
    |> Enum.map(&to_string/1)
    |> Enum.intersperse(?.)
  end

  defp format_metric_value(%Metrics.Counter{}, _value), do: "1|c"
  defp format_metric_value(%Metrics.Distribution{}, value), do: "#{value}|ms"
  defp format_metric_value(%Metrics.LastValue{}, value), do: "#{value}|g"
  defp format_metric_value(%Metrics.Sum{}, value) when value >= 0, do: "+#{value}|g"
  defp format_metric_value(%Metrics.Sum{}, value), do: "#{value}|g"
end
