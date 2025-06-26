defmodule RubberDuckEngines do
  @moduledoc """
  Analysis engines for the RubberDuck coding assistant system.
  
  This module provides the main API for interacting with analysis engines,
  including engine registration, analysis requests, and system monitoring.
  """

  alias RubberDuckEngines.EngineManager
  alias RubberDuckCore.Analysis

  @doc """
  Hello world - preserved from original implementation.

  ## Examples

      iex> RubberDuckEngines.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Registers a new analysis engine.
  """
  def register_engine(engine_module, config \\ %{}) do
    EngineManager.register_engine(engine_module, config)
  end

  @doc """
  Unregisters an analysis engine.
  """
  def unregister_engine(engine_module) do
    EngineManager.unregister_engine(engine_module)
  end

  @doc """
  Lists all registered engines and their capabilities.
  """
  def list_engines do
    EngineManager.list_engines()
  end

  @doc """
  Submits an analysis request to the appropriate engine.
  """
  def analyze(analysis_request) do
    EngineManager.analyze(analysis_request)
  end

  @doc """
  Gets the health status of all engines.
  """
  def health_status do
    EngineManager.health_status()
  end

  @doc """
  Finds engines capable of handling a specific analysis type.
  """
  def find_engines_for(analysis_type) do
    EngineManager.find_engines_for(analysis_type)
  end

  @doc """
  Starts the default analysis engines.
  """
  def start_default_engines do
    engines = [
      {RubberDuckEngines.Engines.CodeReviewEngine, %{}},
      {RubberDuckEngines.Engines.DocumentationEngine, %{}},
      {RubberDuckEngines.Engines.TestingEngine, %{}}
    ]
    
    Enum.map(engines, fn {engine_module, config} ->
      case register_engine(engine_module, config) do
        {:ok, pid} -> {:ok, engine_module, pid}
        error -> {:error, engine_module, error}
      end
    end)
  end

  @doc """
  Creates a new analysis request.
  """
  def new_analysis(type, input, opts \\ []) do
    Analysis.new([
      type: type,
      input: input,
      engine: Keyword.get(opts, :engine),
      conversation_id: Keyword.get(opts, :conversation_id)
    ])
  end
end
