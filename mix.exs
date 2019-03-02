defmodule TelemetryMetricsStatsd.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics_statsd,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      dialyzer: [ignore_warnings: ".dialyzer_ignore"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support/"]
  defp elixirc_paths(_), do: ["lib/"]

  defp preferred_cli_env do
    [
      docs: :docs,
      dialyzer: :test,
      "coveralls.json": :test
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4"},
      {:telemetry_metrics, github: "beam-telemetry/telemetry_metrics"},
      {:stream_data, "~> 0.4", only: :test},
      {:dialyxir, "~> 0.5", only: :test, runtime: false}
    ]
  end
end
