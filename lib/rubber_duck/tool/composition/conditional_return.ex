defmodule RubberDuck.Tool.Composition.ConditionalReturn do
  @moduledoc """
  Special step for handling conditional workflow returns.

  This step determines which result to return based on the condition step result.
  It's used internally by conditional workflows to return the appropriate result
  from either the success or failure branch.
  """

  @behaviour Reactor.Step

  @doc """
  Returns the appropriate result based on the condition outcome.

  ## Arguments

  - `condition_result` - The result from the condition step
  - `success_result` - The result from the success branch
  - `failure_result` - The result from the failure branch

  ## Returns

  The result from the branch that was executed based on the condition.
  """
  @impl Reactor.Step
  def run(arguments, _context, _options) do
    # Convert Reactor arguments to a map if needed
    args =
      case arguments do
        args when is_map(args) ->
          args

        args when is_list(args) ->
          Enum.reduce(args, %{}, fn arg, acc ->
            Map.put(acc, arg.name, arg.value)
          end)
      end

    condition_result = Map.get(args, :condition_result)
    success_result = Map.get(args, :success_result)
    failure_result = Map.get(args, :failure_result)

    result =
      case condition_result do
        {:ok, _} ->
          # Condition succeeded, return success result
          case success_result do
            {:ok, result} -> {:ok, result}
            {:error, _} = error -> error
            result -> {:ok, result}
          end

        {:error, _} ->
          # Condition failed, return failure result
          case failure_result do
            {:ok, result} -> {:ok, result}
            {:error, _} = error -> error
            result -> {:ok, result}
          end

        result ->
          # Condition returned a non-standard result
          # Treat as success if truthy, failure if falsy
          if result do
            case success_result do
              {:ok, result} -> {:ok, result}
              {:error, _} = error -> error
              result -> {:ok, result}
            end
          else
            case failure_result do
              {:ok, result} -> {:ok, result}
              {:error, _} = error -> error
              result -> {:ok, result}
            end
          end
      end

    # Ensure we always return a valid Reactor.Step result
    case result do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:ok, other}
    end
  end

  @doc """
  No compensation needed for conditional return.
  """
  @impl Reactor.Step
  def compensate(_arguments, _result, _context, _options) do
    :ok
  end

  @doc """
  Conditional return can be undone by doing nothing.
  """
  @impl Reactor.Step
  def undo(_arguments, _result, _context, _options) do
    :ok
  end

  @doc """
  Conditional return steps can run asynchronously.
  """
  @impl Reactor.Step
  def async?(_) do
    true
  end

  @doc """
  Conditional return can always run.
  """
  @impl Reactor.Step
  def can?(_arguments, _context) do
    :ok
  end
end
