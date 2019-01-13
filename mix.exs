defmodule TelemetryMetricsStatsd.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics_statsd,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.3"},
      {:telemetry_metrics, github: "beam-telemetry/telemetry_metrics"}
    ]
  end
end
