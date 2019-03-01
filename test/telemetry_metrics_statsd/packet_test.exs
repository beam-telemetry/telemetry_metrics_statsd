defmodule TelemetryMetricsStatsd.PacketTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TelemetryMetricsStatsd.Packet

  property "it returns packets of binaries under given size joined with given binary" do
    check all max_packet_size <- positive_integer(),
              # We should consider empty binaries in general case, but let's ignore them since we
              # know that we won't be using the in the case of StatsD packets.
              binaries <- list_of(binary(min_length: 1, max_length: max_packet_size)),
              joiner <- binary() do
      packets = Packet.build_packets(binaries, max_packet_size, joiner)

      Enum.reduce(packets, binaries, fn packet, binaries ->
        # each packet needs to be smaller or equal in size to the max_packet_size
        packet_size = byte_size(packet)
        assert packet_size <= max_packet_size
        binaries = drop_packet_binaries(packet, joiner, binaries)

        if binaries != [] do
          # but the packet needs to be as big as possible
          next_binary = Enum.at(binaries, 0)

          assert byte_size(packet <> joiner <> next_binary) > max_packet_size,
                 "packets: #{inspect(packets)}, packet: #{inspect(packet)}, next_binary: #{
                   inspect(next_binary)
                 }, left binaries: #{inspect(binaries)}, packet_size: #{packet_size}"
        end

        binaries
      end)
    end
  end

  defp drop_packet_binaries(packet, joiner, binaries, binaries_so_far \\ [])

  defp drop_packet_binaries(_, _, [], _) do
    []
  end

  defp drop_packet_binaries(packet, joiner, [binary | binaries], binaries_so_far) do
    packet_so_far =
      binaries_so_far
      |> Enum.intersperse(joiner)
      |> :lists.reverse()
      |> :erlang.iolist_to_binary()

    cond do
      packet_so_far == packet ->
        [binary | binaries]

      true ->
        drop_packet_binaries(packet, joiner, binaries, [binary | binaries_so_far])
    end
  end
end
