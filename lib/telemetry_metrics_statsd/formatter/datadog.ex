defmodule TelemetryMetricsStatsd.Formatter.Datadog do
  @moduledoc false

  @behaviour TelemetryMetricsStatsd.Formatter

  alias Telemetry.Metrics

  require Logger

  @impl true
  def format(metric, value, tags) do
    case format_metric_value(metric, value) do
      [] ->
        []

      val ->
        [
          format_metric_name(metric.name),
          ?:,
          val,
          format_sampling_rate(metric.reporter_options),
          format_metric_tags(tags)
        ]
    end
  end

  defp format_metric_name([segment]) do
    [:erlang.atom_to_binary(segment, :utf8)]
  end

  defp format_metric_name([segment | segments]) do
    [:erlang.atom_to_binary(segment, :utf8), ?. | format_metric_name(segments)]
  end

  defp format_metric_value(%Metrics.Counter{}, _value), do: "1|c"

  defp format_metric_value(%Metrics.Summary{}, value), do: [format_number(value), "|h"]

  defp format_metric_value(%Metrics.Distribution{}, value),
    do: [format_number(value), "|d"]

  defp format_metric_value(%Metrics.LastValue{}, value),
    do: [format_number(value), "|g"]

  defp format_metric_value(%Metrics.Sum{}, value), do: [format_number(value), "|c"]

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

  defp format_sampling_rate(reporter_options) do
    case Keyword.get(reporter_options, :sampling_rate, 1.0) do
      rate when rate > 0.0 and rate < 1.0 -> "|@#{rate}"
      _ -> ""
    end
  end
end
