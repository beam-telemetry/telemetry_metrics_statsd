defmodule TelemetryMetricsStatsd.Test.Helpers do
  @moduledoc false

  require Record

  Record.defrecordp(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

  def given_counter(event_name, opts \\ []) do
    Telemetry.Metrics.counter(event_name, opts)
  end

  def given_sum(event_name, opts \\ []) do
    Telemetry.Metrics.sum(event_name, opts)
  end

  def given_last_value(event_name, opts \\ []) do
    Telemetry.Metrics.last_value(event_name, opts)
  end

  def given_summary(event_name, opts \\ []) do
    Telemetry.Metrics.summary(event_name, opts)
  end

  def given_distribution(event_name, opts \\ []) do
    Telemetry.Metrics.distribution(event_name, opts)
  end

  # Adds static host entries to the test/hosts file.
  # The file is configured in test/inetrc, which in turn is generated
  # in a Makefile as a part of a `test` target.
  @spec configure_hosts(%{String.t() => [:inet.ip_address()]}) :: :ok
  def configure_hosts(hosts) do
    hosts_file = Path.expand("../hosts", __DIR__)
    before = :erl_prim_loader.read_file_info(to_charlist(hosts_file))
    IO.inspect(before, label: "BEFORE")
    File.rm_rf!(hosts_file)

    content =
      hosts
      |> Enum.flat_map(fn {hostname, addresses} ->
        Enum.map(addresses, &{hostname, &1})
      end)
      |> Enum.map(fn {hostname, address} ->
        "#{:inet.ntoa(address)} #{hostname}"
      end)
      |> Enum.join("\n")

    # :inet consideres the file as changed when its #file_info record
    # changes: https://erlang.org/doc/man/file.html#type-file_info.
    # Wait 2 seconds to make sure that the #file_info is different
    # due to a different creation time, even when the file's size doesn't change.
    Process.sleep(2000)
    File.write!(hosts_file, content)

    after_ = :erl_prim_loader.read_file_info(to_charlist(hosts_file))
    IO.inspect(after_, label: "AFTER")
    IO.puts("BEFORE == AFTER = #{before == after_}")
    IO.puts(File.read!(hosts_file))

    Wait until all hostnames resolve to configured addresses.
    Enum.each(hosts, fn {hostname, addresses} ->
      hostname = to_charlist(hostname)

      Liveness.eventually(
        fn ->
          case :inet.gethostbyname(hostname) do
            {:ok, hostent(h_addr_list: resolved_addresses)} ->
              IO.puts("resolved: #{inspect(resolved_addresses)}, expected: #{inspect(addresses)}")
              Enum.sort(addresses) == Enum.sort(resolved_addresses)

            {:error, _} = err ->
              IO.inspect(err)
              false
          end
        end,
        250,
        500
      )
    end)
  end
end
