defmodule TelemetryMetricsStatsd.Formatter.Standard do
  @moduledoc false

  @behaviour TelemetryMetricsStatsd.Formatter

  alias Telemetry.Metrics

  require Logger

  @impl true
  def format(metric, value, tags) do
    case format_metric_tags(tags) do
      nil ->
        []

      formatted_tags ->
        case format_metric_value(metric, value) do
          nil ->
            []

          formatted_value ->
            [
              format_metric_name(metric.name),
              formatted_tags,
              ?:,
              formatted_value,
              format_sampling_rate(metric.reporter_options)
            ]
        end
    end
  end

  defp format_metric_name([segment]) do
    [:erlang.atom_to_binary(segment, :utf8)]
  end

  defp format_metric_name([segment | segments]) do
    [:erlang.atom_to_binary(segment, :utf8), ?. | format_metric_name(segments)]
  end

  defp format_metric_tags(tags) do
    do_format_metric_tags(tags)
  catch
    :throw, :empty ->
      nil
  end

  defp do_format_metric_tags([]) do
    []
  end

  defp do_format_metric_tags([{_, ""} | _tags]) do
    throw(:empty)
  end

  defp do_format_metric_tags([{_, nil} | tags]) do
    [?., "nil" | format_metric_tags(tags)]
  end

  defp do_format_metric_tags([{_, tag_value} | tags]) do
    [?., to_string(tag_value) | format_metric_tags(tags)]
  end

  defp format_metric_value(%Metrics.Counter{}, _value), do: "1|c"

  defp format_metric_value(%Metrics.Summary{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|ms"]

  defp format_metric_value(%Metrics.Distribution{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|ms"]

  defp format_metric_value(%Metrics.LastValue{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|g"]

  defp format_metric_value(%Metrics.Sum{reporter_options: reporter_options} = sum, value) do
    case Keyword.get(reporter_options, :report_as) do
      :counter -> format_counter_metric_value(sum, value)
      _ -> format_sum_metric_value(sum, value)
    end
  end

  defp format_counter_metric_value(%Metrics.Sum{}, value) when value >= 0,
    do: [value |> round() |> :erlang.integer_to_binary(), "|c"]

  defp format_counter_metric_value(%Metrics.Sum{}, value) do
    Logger.warn(
      "Unable to format negative value: #{inspect(value)} for reporting to StatsD Counter"
    )

    nil
  end

  defp format_sum_metric_value(%Metrics.Sum{}, value) when value >= 0,
    do: [?+, value |> round() |> :erlang.integer_to_binary(), "|g"]

  defp format_sum_metric_value(%Metrics.Sum{}, value),
    do: [value |> round() |> :erlang.integer_to_binary(), "|g"]

  defp format_sampling_rate(reporter_options) do
    case Keyword.get(reporter_options, :sampling_rate, 1.0) do
      rate when rate > 0.0 and rate < 1.0 -> "|@#{rate}"
      _ -> ""
    end
  end
end
