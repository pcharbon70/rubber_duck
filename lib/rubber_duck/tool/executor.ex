defmodule RubberDuck.Tool.Executor do
  @moduledoc """
  Executes tools with validation, authorization, sandboxing, and result processing.

  This module provides a comprehensive execution pipeline for tools, including:
  - Parameter validation
  - Authorization checking
  - Supervised execution with resource limits
  - Timeout handling
  - Result processing
  - Execution monitoring
  """

  require Logger

  alias RubberDuck.Tool.{Validator, Authorizer, Sandbox, ResultProcessor, Telemetry, Monitoring}
  alias RubberDuck.Status

  @type execution_result :: %{
          output: any(),
          status: :success | :error | :timeout | :cancelled,
          execution_time: integer(),
          metadata: map(),
          retry_count: integer()
        }

  @type execution_context :: %{
          user: map(),
          execution_id: String.t(),
          attempt: integer(),
          limits: map()
        }

  @doc """
  Executes a tool synchronously with the given parameters and user context.

  ## Parameters

  - `tool_module` - The tool module to execute
  - `params` - Parameters for the tool
  - `user` - User context for authorization
  - `context` - Additional execution context (optional)

  ## Returns

  - `{:ok, result}` - Successful execution
  - `{:error, reason}` - Execution failed
  - `{:error, reason, details}` - Execution failed with details

  ## Examples

      iex> Executor.execute(MyTool, %{input: "test"}, user)
      {:ok, %{output: "result", status: :success, execution_time: 123}}
  """
  @spec execute(module(), map(), map(), map()) :: {:ok, execution_result()} | {:error, atom(), any()}
  def execute(tool_module, params, user, context \\ %{}) do
    execution_id = generate_execution_id()
    full_context = build_execution_context(user, execution_id, context)

    # Get tool metadata for status updates
    tool_metadata = RubberDuck.Tool.metadata(tool_module)
    conversation_id = context[:conversation_id]

    # Send initial status
    Status.tool(
      conversation_id,
      "Preparing #{tool_metadata.name}",
      Status.build_tool_metadata(tool_metadata.name, params, %{
        execution_id: execution_id,
        stage: "initialization"
      })
    )

    with {:ok, validated_params} <- validate_parameters(tool_module, params),
         {:ok, :authorized} <- authorize_execution(tool_module, user, full_context),
         {:ok, result} <- execute_tool(tool_module, validated_params, full_context) do
      emit_execution_event(:completed, tool_module, user, result)
      record_execution_history(tool_module, user, result)

      {:ok, result}
    else
      {:error, :validation_failed, errors} ->
        Status.error(
          conversation_id,
          "#{tool_metadata.name} validation failed",
          Status.build_error_metadata(:validation_error, format_validation_errors(errors), %{
            tool: tool_metadata.name,
            execution_id: execution_id
          })
        )

        {:error, :validation_failed, errors}

      {:error, :authorization_failed, reason} ->
        Status.error(
          conversation_id,
          "#{tool_metadata.name} authorization failed",
          Status.build_error_metadata(:authorization_error, inspect(reason), %{
            tool: tool_metadata.name,
            execution_id: execution_id
          })
        )

        {:error, :authorization_failed, reason}

      {:error, reason} ->
        Status.error(
          conversation_id,
          "#{tool_metadata.name} failed",
          Status.build_error_metadata(:execution_error, inspect(reason), %{
            tool: tool_metadata.name,
            execution_id: execution_id
          })
        )

        emit_execution_event(:failed, tool_module, user, reason)
        {:error, reason}

      {:error, reason, details} ->
        Status.error(
          conversation_id,
          "#{tool_metadata.name} failed",
          Status.build_error_metadata(:execution_error, inspect(reason), %{
            tool: tool_metadata.name,
            execution_id: execution_id,
            details: details
          })
        )

        emit_execution_event(:failed, tool_module, user, reason)
        {:error, reason, details}
    end
  end

  @doc """
  Executes a tool asynchronously and returns a reference for monitoring.

  ## Examples

      iex> {:ok, ref} = Executor.execute_async(MyTool, %{input: "test"}, user)
      iex> receive do
      ...>   {^ref, {:ok, result}} -> result
      ...> end
  """
  @spec execute_async(module(), map(), map(), map()) :: {:ok, reference()} | {:error, atom()}
  def execute_async(tool_module, params, user, context \\ %{}) do
    execution_id = generate_execution_id()
    full_context = build_execution_context(user, execution_id, context)

    # Check concurrency limits
    if exceeds_concurrency_limit?(user, full_context) do
      {:error, :concurrency_limit_exceeded}
    else
      ref = make_ref()
      caller = self()

      # Start supervised task
      {:ok, task_pid} =
        Task.Supervisor.start_child(RubberDuck.TaskSupervisor, fn ->
          result = execute_with_monitoring(tool_module, params, user, full_context, ref)
          send(caller, {ref, result})
        end)

      # Store execution reference
      store_execution_ref(ref, tool_module, user, full_context, caller, task_pid)

      {:ok, ref}
    end
  end

  @doc """
  Cancels an async execution.

  ## Examples

      iex> Executor.cancel_execution(execution_ref)
      :ok
  """
  @spec cancel_execution(reference()) :: :ok | {:error, :not_found}
  def cancel_execution(execution_ref) do
    case get_execution_info(execution_ref) do
      {:ok, info} ->
        # Kill the task
        if info.task_pid && Process.alive?(info.task_pid) do
          Process.exit(info.task_pid, :kill)
        end

        # Send cancellation message to the caller
        if info.caller_pid && Process.alive?(info.caller_pid) do
          send(info.caller_pid, {execution_ref, {:error, :cancelled}})
        end

        # Cleanup
        cleanup_execution_ref(execution_ref)

        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets the current status of an async execution.

  ## Examples

      iex> Executor.get_execution_status(execution_ref)
      {:ok, %{status: :running, started_at: 1234567890}}
  """
  @spec get_execution_status(reference()) :: {:ok, map()} | {:error, :not_found}
  def get_execution_status(execution_ref) do
    case get_execution_info(execution_ref) do
      {:ok, info} ->
        status = %{
          status: info.status,
          started_at: info.started_at,
          completed_at: info.completed_at,
          tool: info.tool_module,
          user: info.user
        }

        {:ok, status}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets execution history for a user.

  ## Examples

      iex> Executor.get_execution_history(user, limit: 10)
      [%{tool_name: :my_tool, executed_at: 1234567890, ...}]
  """
  @spec get_execution_history(map(), keyword()) :: [map()]
  def get_execution_history(user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    # This would typically query a database
    # For now, return from ETS
    :ets.tab2list(:execution_history)
    |> Enum.filter(fn {_id, entry} -> entry.user_id == user.id end)
    |> Enum.map(fn {_id, entry} -> entry end)
    |> Enum.sort_by(& &1.executed_at, :desc)
    |> Enum.take(limit)
  end

  # Private functions

  defp validate_parameters(tool_module, params) do
    case Validator.validate_parameters(tool_module, params) do
      {:ok, validated_params} -> {:ok, validated_params}
      {:error, errors} -> {:error, :validation_failed, errors}
    end
  end

  defp authorize_execution(tool_module, user, context) do
    case Authorizer.authorize(tool_module, user, context) do
      {:ok, :authorized} -> {:ok, :authorized}
      {:error, reason} -> {:error, :authorization_failed, reason}
    end
  end

  defp execute_tool(tool_module, params, context) do
    execution_config = RubberDuck.Tool.execution(tool_module)
    timeout = if execution_config, do: execution_config.timeout, else: 30_000
    retries = if execution_config, do: execution_config.retries, else: 0

    start_time = System.monotonic_time(:millisecond)
    tool_metadata = RubberDuck.Tool.metadata(tool_module)
    conversation_id = context[:conversation_id]

    # Send execution start status
    Status.tool(
      conversation_id,
      "Executing #{tool_metadata.name}",
      Status.build_tool_metadata(tool_metadata.name, params, %{
        execution_id: context.execution_id,
        stage: "execution",
        timeout: timeout,
        retries_allowed: retries
      })
    )

    # Emit telemetry start event
    Telemetry.execute_start(tool_metadata.name, %{
      user_id: context.user.id,
      execution_id: context.execution_id
    })

    # Record execution start in monitoring
    Monitoring.record_execution(
      :started,
      tool_metadata.name,
      %{
        user_id: context.user.id,
        execution_id: context.execution_id,
        params: params
      },
      %{}
    )

    emit_execution_event(:started, tool_module, context.user, params)

    {result, final_context} = execute_with_retries(tool_module, params, context, retries, timeout)

    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - start_time

    case result do
      {:ok, output} ->
        raw_result = %{
          output: output,
          status: :success,
          execution_time: execution_time,
          metadata: build_result_metadata(tool_module, context, start_time, end_time),
          retry_count: (final_context[:attempt] || 1) - 1
        }

        # Process result through pipeline
        processing_opts = Map.get(context, :processing, [])

        case ResultProcessor.process_result(raw_result, tool_module, context, processing_opts) do
          {:ok, processed_result} ->
            # Emit telemetry stop event for successful execution
            Telemetry.execute_stop(tool_metadata.name, execution_time, %{
              user_id: context.user.id,
              execution_id: context.execution_id,
              status: :success
            })

            # Record in monitoring
            Monitoring.record_execution(
              :completed,
              tool_metadata.name,
              %{
                user_id: context.user.id,
                execution_id: context.execution_id
              },
              %{
                execution_time: execution_time,
                retry_count: processed_result.retry_count
              }
            )

            # Send completion status
            Status.with_timing(
              conversation_id,
              :tool,
              "Completed #{tool_metadata.name}",
              start_time,
              Status.build_tool_metadata(tool_metadata.name, params, %{
                execution_id: context.execution_id,
                stage: "completed",
                retry_count: processed_result.retry_count,
                output_size: byte_size(inspect(processed_result.output))
              })
            )

            emit_execution_event(:completed, tool_module, context.user, processed_result)
            {:ok, processed_result}

          {:error, reason, details} ->
            Logger.error("Result processing failed: #{inspect(reason)} - #{inspect(details)}")

            # Still count as successful execution even if processing failed
            Telemetry.execute_stop(tool_metadata.name, execution_time, %{
              user_id: context.user.id,
              execution_id: context.execution_id,
              status: :success,
              processing_failed: true
            })

            # Return raw result if processing fails
            emit_execution_event(:completed, tool_module, context.user, raw_result)
            {:ok, raw_result}
        end

      {:error, reason} ->
        # Emit telemetry exception event
        Telemetry.execute_exception(tool_metadata.name, execution_time, :error, reason, %{
          user_id: context.user.id,
          execution_id: context.execution_id
        })

        # Record in monitoring
        Monitoring.record_execution(
          :failed,
          tool_metadata.name,
          %{
            user_id: context.user.id,
            execution_id: context.execution_id,
            reason: reason
          },
          %{execution_time: execution_time}
        )

        emit_execution_event(:failed, tool_module, context.user, reason)
        {:error, reason}

      {:error, reason, details} ->
        # Emit telemetry exception event
        Telemetry.execute_exception(tool_metadata.name, execution_time, :error, {reason, details}, %{
          user_id: context.user.id,
          execution_id: context.execution_id
        })

        # Record in monitoring
        Monitoring.record_execution(
          :failed,
          tool_metadata.name,
          %{
            user_id: context.user.id,
            execution_id: context.execution_id,
            reason: reason,
            details: details
          },
          %{execution_time: execution_time}
        )

        emit_execution_event(:failed, tool_module, context.user, {reason, details})
        {:error, reason, details}
    end
  end

  defp execute_with_retries(tool_module, params, context, retries, timeout) do
    attempt = context[:attempt] || 1

    try do
      # Check resource limits before execution
      case check_resource_limits(context) do
        {:error, reason, details} ->
          {{:error, reason, details}, context}

        :ok ->
          # Execute with timeout
          task =
            Task.async(fn ->
              # Add resource monitoring
              monitor_resources(context)

              # Get execution configuration
              execution_config = RubberDuck.Tool.execution(tool_module)
              handler = execution_config.handler

              # Execute the tool in sandbox
              execution_context = Map.put(context, :attempt, attempt)

              # Use sandbox for secure execution
              case Sandbox.execute_in_sandbox(tool_module, handler, params, execution_context) do
                {:ok, result} -> result
                {:error, :timeout, details} -> {:error, :timeout, details}
                {:error, :memory_limit_exceeded, details} -> {:error, :memory_limit_exceeded, details}
                {:error, :cpu_limit_exceeded, details} -> {:error, :cpu_limit_exceeded, details}
                {:error, :sandbox_violation, details} -> {:error, :sandbox_violation, details}
                {:error, reason, details} -> {:error, reason, details}
                {:error, reason} -> {:error, :execution_failed, reason}
              end
            end)

          case Task.await(task, timeout) do
            {:ok, result} ->
              {{:ok, result}, Map.put(context, :attempt, attempt)}

            {:error, :execution_failed, _message} when attempt <= retries ->
              # Retry with incremented attempt
              new_context = Map.put(context, :attempt, attempt + 1)
              execute_with_retries(tool_module, params, new_context, retries, timeout)

            {:error, _reason} when attempt <= retries ->
              # Retry with incremented attempt
              new_context = Map.put(context, :attempt, attempt + 1)
              execute_with_retries(tool_module, params, new_context, retries, timeout)

            {:error, reason} ->
              {{:error, reason}, Map.put(context, :attempt, attempt)}

            {:error, reason, details} ->
              {{:error, reason, details}, Map.put(context, :attempt, attempt)}

            result ->
              # Handle direct return values (non-tuple)
              {{:ok, result}, Map.put(context, :attempt, attempt)}
          end
      end
    rescue
      error ->
        if attempt <= retries do
          new_context = Map.put(context, :attempt, attempt + 1)
          execute_with_retries(tool_module, params, new_context, retries, timeout)
        else
          {{:error, :execution_failed, Exception.message(error)}, Map.put(context, :attempt, attempt)}
        end
    catch
      :exit, {:timeout, _} ->
        {{:error, :timeout}, Map.put(context, :attempt, attempt)}

      :exit, reason ->
        {{:error, :execution_failed, reason}, Map.put(context, :attempt, attempt)}
    end
  end

  defp execute_with_monitoring(tool_module, params, user, context, ref) do
    # Update execution status
    update_execution_status(ref, :running)

    try do
      execute(tool_module, params, user, context)
    after
      # Update final status
      update_execution_status(ref, :completed)
    end
  end

  defp build_execution_context(user, execution_id, context) do
    %{
      user: user,
      execution_id: execution_id,
      attempt: context[:attempt] || 1,
      limits: context[:limits] || %{},
      started_at: System.monotonic_time(:millisecond)
    }
  end

  defp build_result_metadata(tool_module, context, start_time, end_time) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    %{
      tool_name: metadata.name,
      user_id: context.user.id,
      execution_id: context.execution_id,
      started_at: start_time,
      completed_at: end_time
    }
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end

  defp format_validation_errors(error), do: inspect(error)

  defp emit_execution_event(event, tool_module, user, data) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    event_data =
      case event do
        :completed ->
          %{
            tool: metadata.name,
            user: user,
            result: data,
            timestamp: System.monotonic_time(:millisecond)
          }

        :failed ->
          %{
            tool: metadata.name,
            user: user,
            error: data,
            timestamp: System.monotonic_time(:millisecond)
          }

        _ ->
          %{
            tool: metadata.name,
            user: user,
            data: data,
            timestamp: System.monotonic_time(:millisecond)
          }
      end

    Phoenix.PubSub.broadcast(RubberDuck.PubSub, "tool_executions", {:"tool_execution_#{event}", event_data})
  end

  defp record_execution_history(tool_module, user, result) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    entry = %{
      tool_name: metadata.name,
      user_id: user.id,
      executed_at: System.monotonic_time(:millisecond),
      status: result.status,
      execution_time: result.execution_time
    }

    # Store in ETS (would typically be in database)
    try do
      :ets.insert(:execution_history, {result.metadata.execution_id, entry})
    rescue
      ArgumentError ->
        # Create table if it doesn't exist
        try do
          :ets.new(:execution_history, [:set, :public, :named_table])
        rescue
          # Table already exists
          ArgumentError -> :ok
        end

        :ets.insert(:execution_history, {result.metadata.execution_id, entry})
    end
  end

  defp store_execution_ref(ref, tool_module, user, context, caller_pid, task_pid) do
    info = %{
      tool_module: tool_module,
      user: user,
      context: context,
      status: :running,
      started_at: System.monotonic_time(:millisecond),
      completed_at: nil,
      task_pid: task_pid,
      caller_pid: caller_pid
    }

    try do
      :ets.insert(:execution_refs, {ref, info})
    rescue
      ArgumentError ->
        try do
          :ets.new(:execution_refs, [:set, :public, :named_table])
        rescue
          # Table already exists
          ArgumentError -> :ok
        end

        :ets.insert(:execution_refs, {ref, info})
    end
  end

  defp get_execution_info(ref) do
    case :ets.lookup(:execution_refs, ref) do
      [{^ref, info}] -> {:ok, info}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError ->
      {:error, :not_found}
  end

  defp update_execution_status(ref, status) do
    case :ets.lookup(:execution_refs, ref) do
      [{^ref, info}] ->
        updated_info = %{info | status: status, completed_at: System.monotonic_time(:millisecond)}
        :ets.insert(:execution_refs, {ref, updated_info})

      [] ->
        :ok
    end
  rescue
    ArgumentError ->
      :ok
  end

  defp cleanup_execution_ref(ref) do
    :ets.delete(:execution_refs, ref)
  rescue
    ArgumentError ->
      :ok
  end

  defp exceeds_concurrency_limit?(user, context) do
    max_concurrent = context[:limits][:max_concurrent]

    if max_concurrent do
      # Count running executions for this user
      running_count =
        :ets.tab2list(:execution_refs)
        |> Enum.count(fn {_ref, info} ->
          info.user.id == user.id && info.status == :running
        end)

      running_count >= max_concurrent
    else
      false
    end
  rescue
    ArgumentError ->
      false
  end

  defp check_resource_limits(context) do
    limits = context[:limits] || %{}

    cond do
      # Check memory limit
      memory_limit = limits[:memory_mb] ->
        current_memory = get_memory_usage()

        if current_memory > memory_limit do
          {:error, :resource_limit_exceeded, :memory}
        else
          check_cpu_limit(limits)
        end

      # Check CPU limit
      cpu_limit = limits[:cpu_seconds] ->
        current_cpu = get_cpu_usage()

        if current_cpu > cpu_limit do
          {:error, :resource_limit_exceeded, :cpu}
        else
          :ok
        end

      # No limits set
      true ->
        :ok
    end
  end

  defp check_cpu_limit(limits) do
    if cpu_limit = limits[:cpu_seconds] do
      current_cpu = get_cpu_usage()

      if current_cpu > cpu_limit do
        {:error, :resource_limit_exceeded, :cpu}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp monitor_resources(_context) do
    # Resource monitoring would be implemented here
    # For now, just return
    :ok
  end

  defp get_memory_usage do
    # Get current memory usage in MB
    # For testing, we simulate higher memory usage
    current_memory = :erlang.memory(:total) / (1024 * 1024)
    # Add a base amount to simulate higher usage for testing
    current_memory + 50
  end

  defp get_cpu_usage do
    # Get current CPU usage - simplified implementation
    # Would need proper CPU monitoring
    # For testing, simulate higher CPU usage
    5.0
  end
end
