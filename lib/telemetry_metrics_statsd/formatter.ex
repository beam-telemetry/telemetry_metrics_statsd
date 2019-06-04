defmodule TelemetryMetricsStatsd.Formatter do
  @moduledoc false

  alias Telemetry.Metrics

  @spec format(
          prefix :: String.t | nil,
          Telemetry.Metrics.t(),
          :telemetry.event_value(),
          tags :: [
            {Telemetry.Metrics.tag(), term()}
          ],
          tag_format :: TelemetryMetricsStatsd.tag_format()
        ) :: binary()
  def format(prefix, metric, value, tags, tag_format) do
    [
      format_metric_name(prefix, metric.name, tags, tag_format),
      ?:,
      format_metric_value(metric, value),
      format_metric_tags(tag_format, tags)
    ]
    |> :erlang.iolist_to_binary()
  end

  defp format_metric_name(prefix, metric_name, _tags, :datadog), do: format_metric_name(prefix, metric_name, [], :name)
  defp format_metric_name(nil, metric_name, tags, :name), do: format_metric_name(metric_name, tags, :name)
  defp format_metric_name(prefix, metric_name, tags, :name), do: format_metric_name([prefix | metric_name], tags, :name)

  defp format_metric_name(metric_name, tags, :name) do
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

  defp format_metric_tags(:name, _tags), do: []
  defp format_metric_tags(:datadog, tags), do: [?# | combine_tags(tags, :datadog)]

  defp combine_tags(tags, :datadog) do
    Enum.reduce(tags, [], fn
      {k, v}, [] ->
        [["#{k}:#{v}"]]
      {k, v}, acc ->
        [[?,, "#{k}:#{v}"] | acc]
    end)
    |> Enum.reverse()
  end
end
