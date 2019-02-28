defmodule TelemetryMetricsStatsd.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics_statsd,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

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
      {:dialyxir, "~> 1.0.0-rc.3", only: :test, runtime: false},
      {:excoveralls, "~> 0.10.0", only: :test, runtime: false}
    ]
  end
end
