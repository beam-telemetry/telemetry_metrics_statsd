defmodule TelemetryMetricsStatsd.Formatter.Standard do
  @moduledoc false

  @behaviour TelemetryMetricsStatsd.Formatter

  alias Telemetry.Metrics

  @impl true
  def format(metric, value, tags) do
    [
      format_metric_name(metric.name),
      format_metric_tags(tags),
      ?:,
      format_metric_value(metric, value)
    ]
  end

  defp format_metric_name([segment]) do
    [:erlang.atom_to_binary(segment, :utf8)]
  end

  defp format_metric_name([segment | segments]) do
    [:erlang.atom_to_binary(segment, :utf8), ?. | format_metric_name(segments)]
  end

  defp format_metric_tags([]) do
    []
  end

  defp format_metric_tags([{_, nil} | tags]) do
    [?., "nil" | format_metric_tags(tags)]
  end

  defp format_metric_tags([{_, tag_value} | tags]) do
    [?., to_string(tag_value) | format_metric_tags(tags)]
  end

  defp format_metric_value(%Metrics.Counter{}, _value), do: "1|c"

  defp format_metric_value(%Metrics.Summary{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|ms"]

  defp format_metric_value(%Metrics.Distribution{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|ms"]

  defp format_metric_value(%Metrics.LastValue{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|g"]

  defp format_metric_value(%Metrics.Sum{}, value) when value >= 0,
    do: [?+, value |> round() |> :erlang.integer_to_binary(), "|g"]

  defp format_metric_value(%Metrics.Sum{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|g"]
end
