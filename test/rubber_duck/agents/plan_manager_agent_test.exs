defmodule RubberDuck.Agents.PlanManagerAgentTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Agents.PlanManagerAgent
  alias RubberDuck.Agents.PlanManagerAgent.{
    CreatePlanAction,
    UpdatePlanAction,
    TransitionPlanAction,
    QueryPlansAction,
    DeletePlanAction,
    GetMetricsAction
  }
  
  setup do
    # Clean up any existing plans from previous tests
    case Ash.read(RubberDuck.Planning.Plan) do
      {:ok, plans} -> Enum.each(plans, &Ash.destroy!/1)
      _ -> :ok
    end
    
    # Start the agent for testing
    {:ok, agent} = start_supervised({PlanManagerAgent, [id: "test_plan_manager"]})
    
    # Get initial agent state
    initial_state = %{
      plans: %{},
      plan_locks: %{},
      metrics: %{
        plans_created: 0,
        plans_completed: 0,
        plans_failed: 0,
        active_plans: 0
      },
      query_cache: %{},
      workflows: %{},
      config: %{
        max_concurrent_plans: 10,
        lock_timeout: 30_000,
        cache_ttl: 60_000,
        validation_required: false
      }
    }
    
    %{agent: agent, initial_state: initial_state}
  end
  
  describe "CreatePlanAction" do
    test "creates a new plan successfully", %{initial_state: state} do
      params = %{
        name: "Test Plan",
        description: "A test plan",
        type: :feature,
        context: %{test: true},
        dependencies: %{},
        constraints_data: %{}
      }
      
      context = %{agent: %{state: state}}
      
      assert {:ok, result, updated_context} = CreatePlanAction.run(params, context)
      
      assert is_binary(result.plan_id)
      assert result.status == :creating
      assert result.plan.name == "Test Plan"
      
      # Check metrics were updated
      assert updated_context.agent.state.metrics.plans_created == 1
      assert updated_context.agent.state.metrics.active_plans == 1
    end
    
    test "respects max concurrent plans limit", %{initial_state: state} do
      # Fill up to max capacity
      full_plans = for i <- 1..10, into: %{} do
        {"plan_#{i}", %{plan: %{id: "plan_#{i}"}, status: :active}}
      end
      
      state_at_limit = %{state | plans: full_plans}
      context = %{agent: %{state: state_at_limit}}
      
      params = %{
        name: "Overflow Plan",
        description: "Should be rejected",
        type: :feature
      }
      
      assert {:error, :max_plans_reached} = CreatePlanAction.run(params, context)
    end
  end
  
  describe "UpdatePlanAction" do
    test "updates an existing plan", %{initial_state: state} do
      # Create a real plan first
      {:ok, existing_plan} = Ash.create(RubberDuck.Planning.Plan, %{
        name: "Original Name",
        description: "Original Description",
        type: :feature,
        context: %{},
        dependencies: %{},
        constraints_data: %{}
      })
      
      state_with_plan = %{state | 
        plans: %{
          existing_plan.id => %{
            plan: existing_plan,
            status: :draft,
            created_at: DateTime.utc_now()
          }
        }
      }
      
      params = %{
        plan_id: existing_plan.id,
        updates: %{
          name: "Updated Name",
          description: "Updated Description"
        },
        validate: false
      }
      
      context = %{agent: %{state: state_with_plan}}
      
      assert {:ok, result, _updated_context} = UpdatePlanAction.run(params, context)
      
      assert result.plan_id == existing_plan.id
      assert result.updated_fields == [:name, :description]
    end
    
    test "fails when plan doesn't exist", %{initial_state: state} do
      params = %{
        plan_id: "nonexistent_plan",
        updates: %{name: "New Name"},
        validate: false
      }
      
      context = %{agent: %{state: state}}
      
      assert {:error, :plan_not_found} = UpdatePlanAction.run(params, context)
    end
  end
  
  describe "TransitionPlanAction" do
    test "transitions plan state correctly", %{initial_state: state} do
      # Create a real plan
      {:ok, existing_plan} = Ash.create(RubberDuck.Planning.Plan, %{
        name: "Transition Test Plan",
        type: :feature,
        context: %{},
        dependencies: %{},
        constraints_data: %{}
      })
      
      state_with_plan = %{state |
        plans: %{
          existing_plan.id => %{
            plan: existing_plan,
            status: :draft
          }
        }
      }
      
      params = %{
        plan_id: existing_plan.id,
        new_status: :ready,
        reason: "Validation passed"
      }
      
      context = %{agent: %{state: state_with_plan}}
      
      assert {:ok, result, _updated_context} = TransitionPlanAction.run(params, context)
      
      assert result.old_status == :draft
      assert result.new_status == :ready
    end
    
    test "rejects invalid state transitions", %{initial_state: state} do
      plan_id = "plan_invalid_transition"
      existing_plan = %{
        id: plan_id,
        status: :completed
      }
      
      state_with_plan = %{state |
        plans: %{
          plan_id => %{
            plan: existing_plan,
            status: :completed
          }
        }
      }
      
      params = %{
        plan_id: plan_id,
        new_status: :executing,
        reason: "Invalid attempt"
      }
      
      context = %{agent: %{state: state_with_plan}}
      
      assert {:error, {:invalid_transition, :completed, :executing}} = 
        TransitionPlanAction.run(params, context)
    end
  end
  
  describe "QueryPlansAction" do
    test "queries plans with filters", %{initial_state: state} do
      # Add some test plans
      plans = %{
        "plan_1" => %{
          plan: %{id: "plan_1", status: :draft, name: "Plan 1"},
          status: :draft,
          created_at: DateTime.utc_now()
        },
        "plan_2" => %{
          plan: %{id: "plan_2", status: :ready, name: "Plan 2"},
          status: :ready,
          created_at: DateTime.utc_now()
        },
        "plan_3" => %{
          plan: %{id: "plan_3", status: :draft, name: "Plan 3"},
          status: :draft,
          created_at: DateTime.utc_now()
        }
      }
      
      state_with_plans = %{state | plans: plans}
      
      params = %{
        filters: %{status: :draft},
        sort_by: :name,
        order: :asc,
        limit: 10,
        offset: 0
      }
      
      context = %{agent: %{state: state_with_plans}}
      
      assert {:ok, result, _updated_context} = QueryPlansAction.run(params, context)
      
      assert result.total == 2
      assert length(result.plans) == 2
      # All results should have draft status
      assert Enum.all?(result.plans, fn p -> p.status == :draft end)
    end
    
    test "uses cache for repeated queries", %{initial_state: state} do
      params = %{
        filters: %{},
        sort_by: :created_at,
        order: :desc,
        limit: 20,
        offset: 0
      }
      
      context = %{agent: %{state: state}}
      
      # First query - should miss cache
      assert {:ok, _result1, updated_context1} = QueryPlansAction.run(params, context)
      
      # Cache should now have an entry
      assert map_size(updated_context1.agent.state.query_cache) == 1
      
      # Second query with same params - should hit cache
      assert {:ok, _result2, updated_context2} = QueryPlansAction.run(params, updated_context1)
      
      # Cache size should remain the same
      assert map_size(updated_context2.agent.state.query_cache) == 1
    end
  end
  
  describe "DeletePlanAction" do
    test "deletes a plan successfully", %{initial_state: state} do
      # Create a real plan
      {:ok, existing_plan} = Ash.create(RubberDuck.Planning.Plan, %{
        name: "Plan to Delete",
        type: :feature,
        context: %{},
        dependencies: %{},
        constraints_data: %{}
      })
      
      state_with_plan = %{state |
        plans: %{
          existing_plan.id => %{
            plan: existing_plan,
            status: :draft
          }
        },
        metrics: %{state.metrics | active_plans: 1}
      }
      
      params = %{
        plan_id: existing_plan.id,
        force: false
      }
      
      context = %{agent: %{state: state_with_plan}}
      
      assert {:ok, result, updated_context} = DeletePlanAction.run(params, context)
      
      assert result.plan_id == existing_plan.id
      assert Map.has_key?(result, :deleted_at)
      
      # Plan should be removed from state
      refute Map.has_key?(updated_context.agent.state.plans, existing_plan.id)
      assert updated_context.agent.state.metrics.active_plans == 0
    end
    
    test "prevents deletion of active plans without force", %{initial_state: state} do
      plan_id = "active_plan"
      existing_plan = %{
        id: plan_id,
        status: :executing
      }
      
      state_with_plan = %{state |
        plans: %{
          plan_id => %{
            plan: existing_plan,
            status: :executing
          }
        }
      }
      
      params = %{
        plan_id: plan_id,
        force: false
      }
      
      context = %{agent: %{state: state_with_plan}}
      
      assert {:error, {:cannot_delete_active_plan, :executing}} = 
        DeletePlanAction.run(params, context)
    end
  end
  
  describe "GetMetricsAction" do
    test "retrieves all metrics", %{initial_state: state} do
      # Set up some metrics
      state_with_metrics = %{state |
        metrics: %{
          plans_created: 10,
          plans_completed: 7,
          plans_failed: 2,
          active_plans: 1
        }
      }
      
      params = %{
        metric_types: [:all],
        time_range: :all_time
      }
      
      context = %{agent: %{state: state_with_metrics}}
      
      assert {:ok, metrics, _context} = GetMetricsAction.run(params, context)
      
      assert metrics.plans_created == 10
      assert metrics.plans_completed == 7
      assert metrics.plans_failed == 2
      assert metrics.active_plans == 1
      assert_in_delta metrics.success_rate, 77.77777777777777, 0.0001
    end
    
    test "retrieves specific metrics only", %{initial_state: state} do
      state_with_metrics = %{state |
        metrics: %{
          plans_created: 10,
          plans_completed: 7,
          plans_failed: 2,
          active_plans: 1
        }
      }
      
      params = %{
        metric_types: [:plans_created, :active_plans],
        time_range: :all_time
      }
      
      context = %{agent: %{state: state_with_metrics}}
      
      assert {:ok, metrics, _context} = GetMetricsAction.run(params, context)
      
      assert metrics.plans_created == 10
      assert metrics.active_plans == 1
      refute Map.has_key?(metrics, :plans_completed)
      refute Map.has_key?(metrics, :plans_failed)
    end
  end
  
  describe "signal handling" do
    test "signal mappings are configured correctly" do
      mappings = PlanManagerAgent.signal_mappings()
      
      assert Map.has_key?(mappings, "plan.create")
      assert Map.has_key?(mappings, "plan.update")
      assert Map.has_key?(mappings, "plan.transition")
      assert Map.has_key?(mappings, "plan.query")
      assert Map.has_key?(mappings, "plan.delete")
      assert Map.has_key?(mappings, "plan.metrics")
      assert Map.has_key?(mappings, "plan.validate")
      assert Map.has_key?(mappings, "plan.execute")
      
      # Each mapping should have an action and extractor
      Enum.each(mappings, fn {_signal, {action, extractor}} ->
        assert is_atom(action)
        assert is_function(extractor, 1)
      end)
    end
  end
end