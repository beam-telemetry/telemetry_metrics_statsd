defmodule TelemetryMetricsStatsd.Packet do
  @moduledoc false

  require Logger

  @spec build_packets([binary()], size :: non_neg_integer(), joiner :: binary()) :: [binary()]
  def build_packets(binaries, max_size, joiner)
      when is_integer(max_size) and max_size > 0 and is_binary(joiner) do
    build_packets(binaries, max_size, joiner, [{[], 0, 0}])
  end

  # Only the first element of `rest` is a pair of packet and its size.
  defp build_packets(
         [],
         _max_size,
         joiner,
         [{packet_binaries, _, _} | rest]
       ) do
    packet = join_binaries(packet_binaries, joiner)
    :lists.reverse([packet | rest])
  end

  defp build_packets(
         [binary | binaries],
         max_size,
         joiner,
         acc = [{packet_binaries, packet_binaries_count, packet_binaries_size} | rest]
       ) do
    binary_size = byte_size(binary)

    with {_, true} <- {:binary_size_check, binary_size <= max_size},
         new_packet_binaries_count = packet_binaries_count + 1,
         new_packet_binaries_size = packet_binaries_size + binary_size,
         new_packet_size =
           new_packet_binaries_size + (new_packet_binaries_count - 1) * byte_size(joiner),
         {_, true} <- {:packet_size_check, new_packet_size <= max_size} do
      packet_binaries = [binary | packet_binaries]

      build_packets(binaries, max_size, joiner, [
        {packet_binaries, new_packet_binaries_count, new_packet_binaries_size} | rest
      ])
    else
      {:binary_size_check, false} ->
        Logger.warning(
          "Binary size #{binary_size} bytes exceeds the provided maximum packet size #{max_size} bytes. You might increase it via the :mtu config."
        )

        build_packets(binaries, max_size, joiner, acc)

      {:packet_size_check, false} ->
        packet = join_binaries(packet_binaries, joiner)
        build_packets(binaries, max_size, joiner, [{[binary], 1, binary_size}, packet | rest])
    end
  end

  defp join_binaries(binaries, joiner) do
    binaries
    |> :lists.reverse()
    |> Enum.intersperse(joiner)
    |> :erlang.iolist_to_binary()
  end
end
