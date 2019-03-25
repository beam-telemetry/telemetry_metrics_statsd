defmodule TelemetryMetricsStatsd.Test.WaitUntil do
  @moduledoc """
  Exports function for asserting that the condition eventually holds true
  """

  defmodule Error do
    defexception [:message]
  end

  @doc """
  Calls the function continuously as long as it returns `false` or raises an exception.

  The function `f` is called `tries` times maximum. `interval` is the smallest amount of time
  between two invocations of `f` (the actual interval might be longer if the function call itself
  takes more time than the provided one).

  When function has been invoked `tries` times, the exception is raised (if the function itself
  has raised an exception during the last invocation, that exception is reraised).
  """
  def wait_until(f, tries \\ 200, interval \\ 100) do
    wait_until(f, tries, interval, %RuntimeError{}, nil)
  end

  defp wait_until(f, 0, _, last_exception, last_stacktrace) when is_function(f) do
    case last_stacktrace do
      nil ->
        raise(last_exception)

      stacktrace ->
        reraise(last_exception, stacktrace)
    end
  end

  defp wait_until(f, tries, interval, _, _) when is_function(f) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case f.() do
        false ->
          sleep_remaining(start_time, interval)
          exception = %Error{message: "function returned false"}
          wait_until(f, tries - 1, interval, exception, nil)

        other ->
          other
      end
    rescue
      e in Error ->
        reraise e, System.stacktrace()

      e ->
        sleep_remaining(start_time, interval)
        wait_until(f, tries - 1, interval, e, System.stacktrace())
    end
  end

  # Sleeps until time passed since `start_time` equals `interval`.
  defp sleep_remaining(start_time, interval) do
    # interval - (now - start)
    remaining = interval - (System.monotonic_time(:millisecond) - start_time)
    if remaining > 0, do: Process.sleep(remaining)
  end
end
