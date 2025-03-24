defmodule TelemetryMetricsStatsd.Options do
  @moduledoc false

  @schema [
    metrics: [
      type: {:list, :any},
      required: true,
      doc:
        "A list of `Telemetry.Metrics` metric definitions that will be published by the reporter."
    ],
    host: [
      type: {:custom, __MODULE__, :host, []},
      default: {127, 0, 0, 1},
      doc:
        "Hostname or IP address of the StatsD server. " <>
          "If it's a hostname, the reporter will resolve it on start and send metrics to the resolved IP address. " <>
          "See `:host_resolution_interval` option to enable periodic hostname lookup."
    ],
    port: [
      type: :non_neg_integer,
      default: 8125,
      doc: "Port of the StatsD server."
    ],
    inet_address_family: [
      type: {:in, [:inet, :inet6, :local]},
      default: :inet,
      doc: "The inet address family, as specified by the Erlang `:inet.address_family type()`."
    ],
    socket_path: [
      type: {:custom, __MODULE__, :socket_path, []},
      doc:
        "Path to the Unix Domain Socket used for publishing instead of the hostname and port. " <>
          ""
    ],
    formatter: [
      type: {:custom, __MODULE__, :formatter, []},
      default: :standard,
      doc:
        "Determines the format of the published metrics. Can be either `:standard` or `:datadog`."
    ],
    global_tags: [
      type: :keyword_list,
      default: [],
      doc:
        "Additional tags published with every metric. " <>
          "Global tags are overridden by the tags specified in the metric definition."
    ],
    prefix: [
      type: {:or, [:string, :atom]},
      doc: "A prefix added to the name of each metric published by the reporter."
    ],
    host_resolution_interval: [
      type: :non_neg_integer,
      doc:
        "When set, the reporter resolves the configured hostname on the specified interval (in milliseconds) " <>
          "instead of looking up the name once on start. If the provided hostname resolves to multiple IP addresses, " <>
          "the first one one the list is used"
    ],
    mtu: [
      type: :non_neg_integer,
      default: 512,
      doc:
        "Maximum Transmission Unit of the link between your application and the StastD server in bytes. " <>
          "If this value is greater than the actual MTU of the link, UDP packets with published metrics will be dropped."
    ],
    flush_timeout: [
      type: :non_neg_integer,
      default: 1000,
      doc:
        "The maximum amount of time, in milliseconds that a metric can sit in an emitter's buffer before being" <>
          "written to the socket. Only used by the UDP emitter."
    ],
    emitters: [
      type: :pos_integer,
      default: 1,
      doc:
        "The number of metrics emitters in the pool. Each metric emitter contains either a UDP or Unix Domain Socket."
    ],
    max_queue_dwell_time: [
      type: :pos_integer,
      doc:
        "The maximum amount of time, in milliseconds, a message should wait in the emitter's message queue before messages are throttled. " <>
          "If a probe message waits in the queue longer than `max_queue_dwell_time`, the percentage of " <>
          "messages emitted is reduced by 50%. The percentage of messages emitted goes up by 1% if a probe message sits in" <>
          "the queue less than the `max_queue_dwell_time`."
    ],
    dwell_time_check_interval: [
      type: :pos_integer,
      default: 1000,
      doc:
        "The cadence of dwell time checks. If the `max_queue_dwell_time` option is set, the queue is " <>
          "probed every `dwell_time_check_interval` milliseconds to see if the dwell time is under the value specified."
    ],
    name: [
      default: TelemetryMetricsStatsd,
      type: :atom,
      doc: "The registered name of the reporter. "
    ]
  ]

  defstruct Keyword.keys(@schema)

  @spec docs() :: String.t()
  def docs do
    NimbleOptions.docs(@schema)
  end

  @spec validate(Keyword.t()) :: {:ok, struct()} | {:error, String.t()}
  def validate(options) do
    case NimbleOptions.validate(options, @schema) do
      {:ok, options} ->
        options = rename_socket_path(options)
        {:ok, struct(__MODULE__, options)}

      {:error, err} ->
        {:error, Exception.message(err)}
    end
  end

  @spec host(term()) ::
          {:ok, :inet.ip_address() | :inet.hostname()} | {:error, String.t()}
  def host(address) when is_tuple(address) do
    case :inet.ntoa(address) do
      {:error, _} ->
        {:error, "expected :host to be a valid IP address, got #{inspect(address)}"}

      _ ->
        {:ok, address}
    end
  end

  def host(address) when is_binary(address) do
    {:ok, to_charlist(address)}
  end

  def host(term) do
    {:error, "expected :host to be an IP address or a hostname, got #{inspect(term)}"}
  end

  @spec socket_path(term()) :: {:ok, :inet.local_address()} | {:error, String.t()}
  def socket_path(path) when is_binary(path), do: {:ok, {:local, to_charlist(path)}}

  def socket_path(term),
    do: {:error, "expected :socket_path to be a string, got #{inspect(term)}"}

  @spec formatter(term()) :: {:ok, TelemetryMetricsStatsd.Formatter.t()} | {:error, String.t()}
  def formatter(:standard), do: {:ok, TelemetryMetricsStatsd.Formatter.Standard}
  def formatter(:datadog), do: {:ok, TelemetryMetricsStatsd.Formatter.Datadog}

  def formatter(term),
    do: {:error, "expected :formatter be either :standard or :datadog, got #{inspect(term)}"}

  defp rename_socket_path(opts) do
    if socket_path = Keyword.get(opts, :socket_path) do
      opts
      |> Keyword.put(:host, socket_path)
      |> Keyword.delete(:socket_path)
    else
      opts
    end
  end
end
