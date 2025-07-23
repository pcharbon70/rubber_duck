defmodule RubberDuck.Errors do
  @moduledoc """
  Custom error types and error handling utilities for RubberDuck.

  This module provides:
  - Domain-specific error types
  - Error normalization functions
  - Tower integration helpers
  """

  defmodule RubberDuckError do
    @moduledoc """
    Base error module for all RubberDuck errors.
    """
    defexception [:message, :details, :code]

    @impl true
    def exception(opts) do
      message = Keyword.get(opts, :message, "An error occurred")
      details = Keyword.get(opts, :details, %{})
      code = Keyword.get(opts, :code, :unknown_error)

      %__MODULE__{
        message: message,
        details: details,
        code: code
      }
    end
  end

  defmodule EngineError do
    @moduledoc """
    Raised when an engine encounters an error during processing.
    """
    defexception [:message, :engine, :input, :reason]

    @impl true
    def exception(opts) do
      engine = Keyword.get(opts, :engine, "unknown")
      reason = Keyword.get(opts, :reason, "processing failed")

      message = Keyword.get(opts, :message, "Engine #{engine} error: #{reason}")
      input = Keyword.get(opts, :input)

      %__MODULE__{
        message: message,
        engine: engine,
        input: input,
        reason: reason
      }
    end
  end

  defmodule LLMError do
    @moduledoc """
    Raised when LLM API calls fail.
    """
    defexception [:message, :provider, :status_code, :response]

    @impl true
    def exception(opts) do
      provider = Keyword.get(opts, :provider, "unknown")
      status_code = Keyword.get(opts, :status_code)
      response = Keyword.get(opts, :response)

      message =
        Keyword.get(opts, :message) ||
          "LLM provider #{provider} returned error#{if status_code, do: " (#{status_code})", else: ""}"

      %__MODULE__{
        message: message,
        provider: provider,
        status_code: status_code,
        response: response
      }
    end
  end

  defmodule ConfigurationError do
    @moduledoc """
    Raised when configuration is invalid or missing.
    """
    defexception [:message, :key, :expected, :actual]

    @impl true
    def exception(opts) do
      key = Keyword.get(opts, :key)
      expected = Keyword.get(opts, :expected)
      actual = Keyword.get(opts, :actual)

      message =
        Keyword.get(opts, :message) ||
          "Invalid configuration#{if key, do: " for #{inspect(key)}", else: ""}"

      %__MODULE__{
        message: message,
        key: key,
        expected: expected,
        actual: actual
      }
    end
  end

  defmodule ServiceUnavailableError do
    @moduledoc """
    Raised when a service is unavailable or circuit breaker is open.
    """
    defexception [:message, :service, :retry_after]

    @impl true
    def exception(opts) do
      service = Keyword.get(opts, :service, "unknown")
      retry_after = Keyword.get(opts, :retry_after)

      message =
        Keyword.get(opts, :message) ||
          "Service #{service} is unavailable#{if retry_after, do: ", retry after #{retry_after}s", else: ""}"

      %__MODULE__{
        message: message,
        service: service,
        retry_after: retry_after
      }
    end
  end

  @doc """
  Reports an exception to Tower with additional context.

  This is a convenience wrapper around Tower.report_exception/3 that
  adds common metadata and normalizes error information.

  ## Examples

      try do
        # some operation
      rescue
        error ->
          RubberDuck.Errors.report_exception(error, __STACKTRACE__,
            user_id: user.id,
            action: "process_code"
          )
      end
  """
  def report_exception(exception, stacktrace, metadata \\ %{}) do
    metadata =
      metadata
      |> normalize_metadata()
      |> Map.put(:application, :rubber_duck)
      |> Map.put(:reported_at, DateTime.utc_now())

    # Report to status system if conversation_id is present
    if conversation_id = metadata[:conversation_id] do
      error_details = normalize_error(exception)

      RubberDuck.Status.error(
        conversation_id,
        "Exception: #{error_details.message}",
        RubberDuck.Status.build_error_metadata(
          error_details.type,
          error_details.message,
          Map.merge(error_details.details, %{
            stacktrace: format_stacktrace(stacktrace),
            metadata: metadata
          })
        )
      )
    end

    # Tower expects a keyword list, not a map
    Tower.report_exception(exception, stacktrace, Map.to_list(metadata))
  end

  @doc """
  Reports a message to Tower as an error event.

  Useful for reporting errors that aren't exceptions, such as
  validation failures or business logic errors.

  ## Examples

      RubberDuck.Errors.report_message(:error, "Invalid input",
        user_id: user.id,
        input: params
      )
  """
  def report_message(level, message, metadata \\ %{}) do
    metadata =
      metadata
      |> normalize_metadata()
      |> Map.put(:application, :rubber_duck)
      |> Map.put(:reported_at, DateTime.utc_now())

    # Report to status system if conversation_id is present
    if conversation_id = metadata[:conversation_id] do
      status_category =
        case level do
          :error -> :error
          :warning -> :warning
          _ -> :info
        end

      RubberDuck.Status.update(
        conversation_id,
        status_category,
        message,
        Map.merge(metadata, %{level: level})
      )
    end

    # Tower expects a keyword list, not a map
    Tower.report_message(level, message, Map.to_list(metadata))
  end

  @doc """
  Normalizes error data into a consistent format for Tower reporting.
  """
  def normalize_error(error) when is_exception(error) do
    %{
      type: error.__struct__,
      message: Exception.message(error),
      details: extract_error_details(error)
    }
  end

  def normalize_error(error) when is_binary(error) do
    %{
      type: :string_error,
      message: error,
      details: %{}
    }
  end

  def normalize_error(error) do
    %{
      type: :unknown_error,
      message: inspect(error),
      details: %{raw: error}
    }
  end

  # Private functions

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_), do: %{}

  defp extract_error_details(%EngineError{} = error) do
    %{
      engine: error.engine,
      input: error.input,
      reason: error.reason
    }
  end

  defp extract_error_details(%LLMError{} = error) do
    %{
      provider: error.provider,
      status_code: error.status_code,
      response: error.response
    }
  end

  defp extract_error_details(%ConfigurationError{} = error) do
    %{
      key: error.key,
      expected: error.expected,
      actual: error.actual
    }
  end

  defp extract_error_details(%ServiceUnavailableError{} = error) do
    %{
      service: error.service,
      retry_after: error.retry_after
    }
  end

  defp extract_error_details(error) do
    error
    |> Map.from_struct()
    |> Map.delete(:__exception__)
    |> Map.delete(:message)
  end

  defp format_stacktrace(stacktrace) do
    stacktrace
    # Limit stacktrace depth
    |> Enum.take(10)
    |> Enum.map(&Exception.format_stacktrace_entry/1)
    |> Enum.join("\n")
  end
end
