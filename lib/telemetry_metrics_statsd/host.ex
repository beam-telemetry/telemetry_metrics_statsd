defmodule TelemetryMetricsStatsd.Host do
  alias TelemetryMetricsStatsd.LogLevel

  require Record
  require Logger

  Record.defrecord(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))


  def configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family
       })
       when is_tuple(host) do
    %{host: host, port: port, inet_address_family: inet_address_family}
  end

  def configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family,
         host_resolution_interval: interval
       })
       when is_integer(interval) do
    {:ok, hostent(h_addr_list: [ip | _ips])} = :inet.gethostbyname(host, inet_address_family)
    schedule_resolve(interval)
    %{host: ip, port: port, inet_address_family: inet_address_family}
  end

  def configure_host_resolution(%{
         host: host,
         port: port,
         inet_address_family: inet_address_family
       }) do
    {:ok, hostent(h_addr_list: [ip | _ips])} = :inet.gethostbyname(host, inet_address_family)
    %{host: ip, port: port, inet_address_family: inet_address_family}
  end

  def configuration_valid?(host, current) do
    case :inet.gethostbyname(host) do
      {:ok, hostent(h_addr_list: ips)} ->
        Enum.member?(ips, current)

      {:error, reason} ->
        Logger.log(
          LogLevel.warning(),
          "Failed to resolve the hostname #{host}: #{inspect(reason)}. " <>
            "Using the previously resolved address of #{:inet.ntoa(current)}."
        )
        true
    end
  end

  def schedule_resolve(interval) do
    Process.send_after(self(), :resolve_host, interval)
  end
end
