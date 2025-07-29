defmodule RubberDuck.Jido.Workflows.Library.Saga do
  @moduledoc """
  Distributed transaction pattern using the Saga approach.
  
  This workflow executes a series of transactions across multiple agents,
  with automatic compensation (rollback) if any step fails.
  
  ## Required Inputs
  
  - `:transactions` - List of transaction steps, each with:
    - `:name` - Transaction identifier
    - `:agent_capability` - Required agent capability
    - `:forward` - Forward transaction function
    - `:compensate` - Compensation function
  
  ## Optional Inputs
  
  - `:isolation_level` - Transaction isolation level
  - `:compensation_strategy` - :backward (default) or :forward
  - `:timeout` - Timeout per transaction in ms (default: 30000)
  
  ## Example
  
      inputs = %{
        transactions: [
          %{
            name: :reserve_inventory,
            agent_capability: :inventory,
            forward: &Inventory.reserve/1,
            compensate: &Inventory.release/1
          },
          %{
            name: :charge_payment,
            agent_capability: :payment,
            forward: &Payment.charge/1,
            compensate: &Payment.refund/1
          },
          %{
            name: :create_shipment,
            agent_capability: :shipping,
            forward: &Shipping.create/1,
            compensate: &Shipping.cancel/1
          }
        ]
      }
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{SelectAgent, ExecuteAgentAction}
  
  input :transactions
  
  step :validate_saga do
    argument :transactions, input(:transactions)
    
    run fn %{transactions: transactions} ->
      case validate_transactions(transactions) do
        :ok -> {:ok, :valid}
        error -> error
      end
    end
  end
  
  step :initialize_saga do
    run fn _arguments ->
      {:ok, %{
        saga_id: generate_saga_id(),
        completed_transactions: [],
        transaction_results: %{},
        status: :running
      }}
    end
  end
  
  step :execute_transactions do
    argument :transactions, input(:transactions)
    argument :saga_state, result(:initialize_saga)
    
    run fn %{transactions: transactions, saga_state: saga_state} ->
      execute_saga_transactions(transactions, saga_state, 30_000, %{})
    end
  end
  
  step :finalize_saga do
    argument :saga_result, result(:execute_transactions)
    
    run fn %{saga_result: saga_result} ->
      case saga_result.status do
        :completed ->
          {:ok, %{
            status: :success,
            results: saga_result.transaction_results
          }}
        
        :compensated ->
          {:ok, %{
            status: :compensated,
            error: saga_result[:error],
            compensated_transactions: saga_result[:compensated_transactions]
          }}
        
        _ ->
          {:error, {:unexpected_status, saga_result.status}}
      end
    end
  end
  
  return :finalize_saga
  
  # Private functions
  
  defp execute_saga_transactions([], state, _timeout, _context) do
    {:ok, %{state | status: :completed}}
  end
  
  defp execute_saga_transactions([txn | remaining], state, timeout, context) do
    with {:ok, agent_id} <- select_agent_for_transaction(txn),
         {:ok, result} <- execute_forward_transaction(agent_id, txn, state, timeout),
         {:ok, new_state} <- update_saga_state(state, txn, result) do
      
      execute_saga_transactions(remaining, new_state, timeout, context)
    else
      {:error, reason} ->
        # Transaction failed, initiate compensation
        compensate_transactions(
          state.completed_transactions,
          state.transaction_results,
          {:transaction_failed, txn.name, reason},
          timeout
        )
    end
  end
  
  defp select_agent_for_transaction(txn) do
    case SelectAgent.run(
      %{
        criteria: {:capability, txn.agent_capability},
        strategy: :least_loaded
      },
      %{},
      []
    ) do
      {:ok, agent_id} when is_binary(agent_id) -> {:ok, agent_id}
      {:ok, [agent_id | _]} -> {:ok, agent_id}
      {:error, reason} -> {:error, {:agent_selection_failed, reason}}
    end
  end
  
  defp execute_forward_transaction(agent_id, txn, state, timeout) do
    action = %{
      type: :transaction,
      name: txn.name,
      operation: :forward,
      function: txn.forward,
      saga_id: state.saga_id,
      context: extract_transaction_context(state)
    }
    
    ExecuteAgentAction.run(
      %{
        agent_id: agent_id,
        action: action,
        params: %{}
      },
      %{},
      timeout: timeout
    )
  end
  
  defp update_saga_state(state, txn, result) do
    new_state = %{state |
      completed_transactions: [{txn, result} | state.completed_transactions],
      transaction_results: Map.put(state.transaction_results, txn.name, result)
    }
    
    {:ok, new_state}
  end
  
  defp compensate_transactions(completed_txns, results, error, timeout) do
    # Execute compensations in reverse order
    compensated = completed_txns
    |> Enum.reverse()
    |> Enum.map(fn {txn, _original_result} ->
      case compensate_transaction(txn, results, timeout) do
        {:ok, _} -> {:compensated, txn.name}
        {:error, reason} -> {:compensation_failed, txn.name, reason}
      end
    end)
    
    {:ok, %{
      status: :compensated,
      error: error,
      compensated_transactions: compensated
    }}
  end
  
  defp compensate_transaction(txn, results, timeout) do
    with {:ok, agent_id} <- select_agent_for_transaction(txn) do
      action = %{
        type: :transaction,
        name: txn.name,
        operation: :compensate,
        function: txn.compensate,
        original_result: Map.get(results, txn.name)
      }
      
      ExecuteAgentAction.run(
        %{
          agent_id: agent_id,
          action: action,
          params: %{}
        },
        %{},
        timeout: timeout
      )
    end
  end
  
  defp extract_transaction_context(state) do
    # Extract relevant context from completed transactions
    state.transaction_results
  end
  
  defp validate_transactions(transactions) when is_list(transactions) do
    if Enum.all?(transactions, &valid_transaction?/1) do
      :ok
    else
      {:error, :invalid_transaction_format}
    end
  end
  defp validate_transactions(_), do: {:error, :transactions_must_be_list}
  
  defp valid_transaction?(%{name: name, agent_capability: cap, forward: fwd, compensate: comp})
       when is_atom(name) and is_atom(cap) and is_function(fwd, 1) and is_function(comp, 1) do
    true
  end
  defp valid_transaction?(_), do: false
  
  defp generate_saga_id do
    "saga_" <> :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  @doc false
  def required_inputs do
    [:transactions]
  end
  
  @doc false
  def available_options do
    [
      isolation_level: "Transaction isolation level",
      compensation_strategy: "Strategy for compensation: :backward or :forward",
      timeout: "Timeout per transaction in milliseconds"
    ]
  end
end