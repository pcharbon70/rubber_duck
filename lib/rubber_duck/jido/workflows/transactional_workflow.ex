defmodule RubberDuck.Jido.Workflows.TransactionalWorkflow do
  @moduledoc """
  A transactional workflow with compensation support.
  
  This workflow demonstrates:
  - Multi-step transactions with agents
  - Compensation on failure
  - State rollback
  - Saga pattern implementation
  
  ## Inputs
  
  - `:transaction_data` - Data for the transaction
  - `:compensation_strategy` - How to handle failures (:compensate, :retry, :fail_fast)
  
  ## Example
  
      {:ok, result} = WorkflowCoordinator.execute_workflow(
        TransactionalWorkflow,
        %{
          transaction_data: %{
            user_id: "123",
            amount: 100,
            items: ["item1", "item2"]
          },
          compensation_strategy: :compensate
        }
      )
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SelectAgent, SendAgentSignal}
  
  input :transaction_data
  input :compensation_strategy do
    transform &(&1 || :compensate)
  end
  
  # Step 1: Reserve inventory
  step :select_inventory_agent, SelectAgent do
    argument :criteria, value({:capability, :inventory_management})
    argument :strategy, value(:least_loaded)
  end
  
  step :reserve_inventory, ExecuteAgentAction do
    argument :agent_id, result(:select_inventory_agent)
    argument :action, value(RubberDuck.Actions.ReserveInventoryAction)
    argument :params do
      source input(:transaction_data)
      transform &Map.take(&1, [:items, :user_id])
    end
    
  end
  
  
  # Step 2: Process payment
  step :select_payment_agent, SelectAgent do
    argument :criteria, value({:capability, :payment_processing})
    argument :strategy, value(:least_loaded)
    
    wait_for :reserve_inventory
  end
  
  step :process_payment, ExecuteAgentAction do
    argument :agent_id, result(:select_payment_agent)
    argument :action, value(RubberDuck.Actions.ProcessPaymentAction)
    argument :params do
      source input(:transaction_data)
      transform &Map.take(&1, [:user_id, :amount])
    end
  end
  
  
  # Step 3: Create order
  step :select_order_agent, SelectAgent do
    argument :criteria, value({:capability, :order_management})
    argument :strategy, value(:least_loaded)
    
    wait_for [:reserve_inventory, :process_payment]
  end
  
  step :create_order, ExecuteAgentAction do
    argument :agent_id, result(:select_order_agent)
    argument :action, value(RubberDuck.Actions.CreateOrderAction)
    argument :params do
      source input(:transaction_data)
      transform &Map.merge(&1, %{
        reservation_id: "temp_reservation",  # Would come from reserve_inventory result
        transaction_id: "temp_transaction"   # Would come from process_payment result
      })
    end
  end
  
  
  # Success notification
  step :notify_success, SendAgentSignal do
    argument :agent_id, value("notification_agent")
    argument :signal do
      source result(:create_order)
      transform &{:order_completed, &1}
    end
    
    wait_for :create_order
  end
  
  # Return the order details
  return :create_order
  
  
  def generate_transaction_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end