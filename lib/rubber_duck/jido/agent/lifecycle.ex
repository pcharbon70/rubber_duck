defmodule RubberDuck.Jido.Agent.Lifecycle do
  @moduledoc """
  Lifecycle hooks for Jido agents.
  
  Provides optional callbacks for agents to hook into various lifecycle events.
  """
  
  @doc """
  Called before agent initialization.
  Can modify the configuration before init/1 is called.
  """
  @callback pre_init(config :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Called after successful agent initialization.
  Can modify the initial state.
  """
  @callback post_init(state :: term()) :: {:ok, term()} | {:error, term()}
  
  @doc """
  Called to check agent health.
  Should return health status and optional metadata.
  """
  @callback health_check(state :: term()) :: {:healthy, map()} | {:unhealthy, map()}
  
  @doc """
  Called before validating state changes.
  """
  @callback on_before_validate_state(old_state :: term(), new_state :: term()) :: 
    {:ok, term()} | {:error, term()}
  
  @doc """
  Called after validating state changes.
  """
  @callback on_after_validate_state(state :: term()) :: {:ok, term()} | {:error, term()}
  
  @doc """
  Called before termination.
  """
  @callback pre_terminate(reason :: term(), state :: term()) :: term()
  
  @optional_callbacks [
    pre_init: 1,
    post_init: 1,
    health_check: 1,
    on_before_validate_state: 2,
    on_after_validate_state: 1,
    pre_terminate: 2
  ]
end