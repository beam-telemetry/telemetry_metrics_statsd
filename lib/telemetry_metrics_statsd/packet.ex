defmodule TelemetryMetricsStatsd.Packet do
  @moduledoc false

  @spec build_packets([binary()], size :: non_neg_integer(), joiner :: binary()) :: [binary()]
  def build_packets(binaries, max_size, joiner)
      when is_integer(max_size) and max_size > 0 and is_binary(joiner) do
    build_packets(binaries, max_size, {joiner, byte_size(joiner)}, [{[], 0, 0}])
  end

  # Only the first element of `acc` is a pair of packet and its size.
  def build_packets([], _, {joiner, _}, [{packet_binaries, _, _} | acc]) do
    packet =
      packet_binaries
      |> :lists.reverse()
      |> Enum.intersperse(joiner)
      |> :erlang.iolist_to_binary()

    :lists.reverse([packet | acc])
  end

  def build_packets([binary | binaries], max_size, {joiner, joiner_size}, [
        {packet_binaries, packet_binaries_count, packet_binaries_size} | acc
      ]) do
    binary_size = byte_size(binary)

    if binary_size > max_size do
      # TODO: this should be probably handled in a nicer way
      raise "Binary size #{binary_size} exceeds the provided maximum packet size #{max_size}. You might increase it via the :mtu config."
    end

    new_packet_binaries_count = packet_binaries_count + 1
    new_packet_binaries_size = packet_binaries_size + binary_size
    packet_size = new_packet_binaries_size + (new_packet_binaries_count - 1) * joiner_size

    if packet_size <= max_size do
      packet_binaries = [binary | packet_binaries]

      build_packets(binaries, max_size, {joiner, joiner_size}, [
        {packet_binaries, new_packet_binaries_count, new_packet_binaries_size} | acc
      ])
    else
      packet =
        packet_binaries
        |> :lists.reverse()
        |> Enum.intersperse(joiner)
        |> :erlang.iolist_to_binary()

      build_packets([binary | binaries], max_size, {joiner, joiner_size}, [
        {[], 0, 0},
        packet | acc
      ])
    end
  end
end
