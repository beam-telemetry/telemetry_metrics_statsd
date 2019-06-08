defmodule TelemetryMetricsStatsd.Formatter.Datadog do
  @moduledoc false

  @behaviour TelemetryMetricsStatsd.Formatter

  alias Telemetry.Metrics

  @impl true
  def format(metric, value, tags) do
    [
      format_metric_name(metric.name),
      ?:,
      format_metric_value(metric, value),
      format_metric_tags(tags)
    ]
  end

  defp format_metric_name([segment]) do
    [:erlang.atom_to_binary(segment, :utf8)]
  end

  defp format_metric_name([segment | segments]) do
    [:erlang.atom_to_binary(segment, :utf8), ?. | format_metric_name(segments)]
  end

  defp format_metric_value(%Metrics.Counter{}, _value), do: "1|c"

  defp format_metric_value(%Metrics.Summary{}, value),
    do: [format_number(value), "|ms"]

  defp format_metric_value(%Metrics.Distribution{}, value),
    do: [format_number(value), "|h"]

  defp format_metric_value(%Metrics.LastValue{}, value),
    do: [format_number(value), "|g"]

  defp format_metric_value(%Metrics.Sum{}, value) when value >= 0,
    do: [?+, format_number(value), "|g"]

  defp format_metric_value(%Metrics.Sum{}, value),
    do: [format_number(value), "|g"]

  defp format_number(number) when is_integer(number) do
    :erlang.integer_to_binary(number)
  end

  defp format_number(number) when is_float(number) do
    Float.to_string(number)
  end

  defp format_metric_tags([]), do: []

  defp format_metric_tags([{k, v} | tags]), do: ["|#", format_tag(k, v), combine_tags(tags)]

  defp combine_tags([]) do
    []
  end

  defp combine_tags([{k, v} | tags]) do
    [?,, format_tag(k, v), combine_tags(tags)]
  end

  defp format_tag(k, nil) do
    [:erlang.atom_to_binary(k, :utf8), ?:, "nil"]
  end

  defp format_tag(k, v) do
    [:erlang.atom_to_binary(k, :utf8), ?:, to_string(v)]
  end
end
