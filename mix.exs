defmodule TelemetryMetricsStatsd.MixProject do
  use Mix.Project

  @version "0.3.0"

  def project do
    [
      app: :telemetry_metrics_statsd,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      dialyzer: [ignore_warnings: ".dialyzer_ignore"],
      docs: docs(),
      description: description(),
      package: package()
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
      format: :test
    ]
  end

  defp deps do
    [
      {:telemetry_metrics, "~> 0.3"},
      {:stream_data, "~> 0.4", only: :test},
      {:dialyxir, "~> 0.5", only: :test, runtime: false},
      {:ex_doc, "~> 0.19", only: :docs}
    ]
  end

  defp docs do
    [
      main: "TelemetryMetricsStatsd",
      canonical: "http://hexdocs.pm/telemetry_metrics_statsd",
      source_url: "https://github.com/beam-telemetry/telemetry_metrics_statsd",
      source_ref: "v#{@version}"
    ]
  end

  defp description do
    """
    Telemetry.Metrics reporter for StastD-compatible metric servers
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_metrics_statsd"}
    ]
  end
end
