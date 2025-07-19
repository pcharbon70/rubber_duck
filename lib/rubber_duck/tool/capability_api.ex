defmodule RubberDuck.Tool.CapabilityAPI do
  @moduledoc """
  Provides API endpoints for tool capability advertisement and discovery.

  This module exposes:
  - Tool capabilities and metadata
  - Quality metrics and performance data
  - Dependency information
  - Composition capabilities (for future use)
  """

  alias RubberDuck.Tool
  alias RubberDuck.Tool.{Registry, ExternalAdapter}

  @doc """
  Lists all available tool capabilities.
  """
  def list_capabilities(opts \\ []) do
    include_metrics = Keyword.get(opts, :include_metrics, false)
    include_examples = Keyword.get(opts, :include_examples, false)
    category_filter = Keyword.get(opts, :category)

    Registry.list()
    |> filter_by_category(category_filter)
    |> Enum.map(fn tool_module ->
      build_capability_info(tool_module, include_metrics, include_examples)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets detailed capability information for a specific tool.
  """
  def get_capability(tool_name, opts \\ []) do
    with {:ok, tool_module} <- Registry.get(tool_name) do
      include_metrics = Keyword.get(opts, :include_metrics, true)
      include_examples = Keyword.get(opts, :include_examples, true)

      capability = build_capability_info(tool_module, include_metrics, include_examples)
      {:ok, capability}
    end
  end

  @doc """
  Gets quality metrics for a tool.
  """
  def get_tool_metrics(tool_name) do
    with {:ok, _tool_module} <- Registry.get(tool_name) do
      # Mock metrics for now - Monitoring.get_tool_metrics not yet implemented
      metrics = %{
        success_rate: 0.95,
        average_duration_ms: 100,
        total_executions: 1000
      }

      {:ok, metrics}
    end
  end

  @doc """
  Lists tool dependencies and requirements.
  """
  def get_dependencies(tool_name) do
    with {:ok, tool_module} <- Registry.get(tool_name) do
      deps = build_dependency_info(tool_module)
      {:ok, deps}
    end
  end

  @doc """
  Advertises composition capabilities (future feature).
  """
  def get_composition_capabilities do
    %{
      supported: false,
      planned_features: [
        "Tool chaining",
        "Conditional execution",
        "Parallel execution",
        "Result transformation pipelines"
      ],
      availability: "Future release"
    }
  end

  @doc """
  Gets OpenAPI specification for all tools.
  """
  def get_openapi_spec do
    tools = Registry.list()

    operations =
      tools
      |> Enum.map(fn tool_module ->
        case ExternalAdapter.convert_metadata(tool_module, :openapi) do
          {:ok, operation} ->
            metadata = Tool.metadata(tool_module)
            {"/tools/#{metadata.name}", %{"post" => operation}}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.into(%{})

    %{
      "openapi" => "3.0.0",
      "info" => %{
        "title" => "RubberDuck Tool API",
        "version" => "1.0.0",
        "description" => "API for executing RubberDuck tools"
      },
      "servers" => [
        %{
          "url" => "/api/v1",
          "description" => "Main API server"
        }
      ],
      "paths" => operations,
      "components" => %{
        "securitySchemes" => %{
          "bearerAuth" => %{
            "type" => "http",
            "scheme" => "bearer"
          }
        }
      },
      "security" => [
        %{"bearerAuth" => []}
      ]
    }
  end

  @doc """
  Searches for tools by capability.
  """
  def search_by_capability(query, opts \\ []) do
    tools = Registry.list()

    # Simple keyword search for now
    # In future, this could use semantic search
    results =
      tools
      |> Enum.map(fn tool_module ->
        score = calculate_relevance_score(tool_module, query)
        {tool_module, score}
      end)
      |> Enum.filter(fn {_, score} -> score > 0 end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> Enum.take(Keyword.get(opts, :limit, 10))
      |> Enum.map(fn {tool_module, score} ->
        metadata = Tool.metadata(tool_module)

        %{
          name: metadata.name,
          description: metadata.description,
          relevance_score: score
        }
      end)

    {:ok, results}
  end

  @doc """
  Gets recommended tools based on context.
  """
  def get_recommendations(context, opts \\ []) do
    # Simple recommendation based on recent usage
    # In future, this could use ML-based recommendations

    recent_tools = context[:recent_tools] || []
    category = context[:preferred_category]

    recommendations =
      Registry.list()
      |> filter_by_category(category)
      |> Enum.reject(fn tool_module ->
        metadata = Tool.metadata(tool_module)
        metadata.name in recent_tools
      end)
      |> Enum.take(Keyword.get(opts, :limit, 5))
      |> Enum.map(&build_recommendation/1)

    {:ok, recommendations}
  end

  # Private functions

  defp filter_by_category(tools, nil), do: tools

  defp filter_by_category(tools, category) do
    Enum.filter(tools, fn tool_module ->
      metadata = Tool.metadata(tool_module)
      metadata[:category] == category
    end)
  end

  defp build_capability_info(tool_module, include_metrics, include_examples) do
    metadata = Tool.metadata(tool_module)

    base_info = %{
      name: metadata.name,
      version: metadata.version || "1.0.0",
      description: metadata.description,
      category: metadata[:category] || "general",
      capabilities: extract_capabilities(tool_module),
      parameters: build_parameter_info(tool_module),
      security: build_security_info(tool_module),
      execution: build_execution_info(tool_module)
    }

    # Add optional data
    info =
      if include_metrics do
        Map.put(base_info, :metrics, get_cached_metrics(metadata.name))
      else
        base_info
      end

    if include_examples do
      examples =
        if function_exported?(tool_module, :examples, 0) do
          tool_module.examples() || []
        else
          []
        end

      Map.put(info, :examples, examples)
    else
      info
    end
  end

  defp extract_capabilities(tool_module) do
    metadata = Tool.metadata(tool_module)
    execution = Tool.execution(tool_module)

    %{
      async_supported: execution[:async] || false,
      streaming_supported: execution[:streaming] || false,
      batch_supported: execution[:batch] || false,
      cancellable: true,
      idempotent: metadata[:idempotent] || false,
      cacheable: metadata[:cacheable] || true
    }
  end

  defp build_parameter_info(tool_module) do
    Tool.parameters(tool_module)
    |> Enum.map(fn param ->
      %{
        name: param.name,
        type: param.type,
        description: param.description,
        required: param[:required] || false,
        default: param[:default],
        constraints: param[:constraints] || %{}
      }
    end)
  end

  defp build_security_info(tool_module) do
    security = Tool.security(tool_module) || %{}

    %{
      sandbox_level: security[:level] || :balanced,
      requires_auth: true,
      rate_limits:
        security[:rate_limits] ||
          %{
            per_minute: 60,
            per_hour: 1000
          },
      capabilities_required: security[:capabilities] || []
    }
  end

  defp build_execution_info(tool_module) do
    execution = Tool.execution(tool_module) || %{}

    %{
      timeout: execution[:timeout] || 30_000,
      retries: execution[:retries] || 3,
      retry_delay: execution[:retry_delay] || 1000,
      max_concurrency: execution[:max_concurrency] || 10
    }
  end

  defp build_dependency_info(tool_module) do
    metadata = Tool.metadata(tool_module)

    %{
      tool_name: metadata.name,
      runtime_dependencies: extract_runtime_deps(tool_module),
      capability_dependencies: extract_capability_deps(tool_module),
      external_services: extract_external_services(tool_module),
      system_requirements: extract_system_requirements(tool_module)
    }
  end

  defp extract_runtime_deps(_tool_module) do
    # In future, analyze the tool implementation
    []
  end

  defp extract_capability_deps(tool_module) do
    security = Tool.security(tool_module) || %{}
    security[:capabilities] || []
  end

  defp extract_external_services(_tool_module) do
    # In future, detect external API calls
    []
  end

  defp extract_system_requirements(tool_module) do
    execution = Tool.execution(tool_module) || %{}

    %{
      min_memory: execution[:min_memory] || "128MB",
      min_cpu: execution[:min_cpu] || "0.1",
      disk_space: execution[:disk_space] || "10MB"
    }
  end

  defp calculate_relevance_score(tool_module, query) do
    metadata = Tool.metadata(tool_module)
    query_lower = String.downcase(query)

    # Simple scoring based on matches
    name_score = if String.contains?(String.downcase(to_string(metadata.name)), query_lower), do: 10, else: 0
    desc_score = if String.contains?(String.downcase(metadata.description), query_lower), do: 5, else: 0

    # Check parameters
    param_score =
      Tool.parameters(tool_module)
      |> Enum.any?(fn param ->
        String.contains?(String.downcase(to_string(param.name)), query_lower) or
          String.contains?(String.downcase(param.description || ""), query_lower)
      end)
      |> then(fn matched -> if matched, do: 3, else: 0 end)

    name_score + desc_score + param_score
  end

  defp build_recommendation(tool_module) do
    metadata = Tool.metadata(tool_module)

    %{
      name: metadata.name,
      description: metadata.description,
      category: metadata[:category] || "general",
      reason: "Popular in #{metadata[:category] || "general"} category"
    }
  end

  defp get_cached_metrics(_tool_name) do
    # Simple mock metrics for now
    # In production, this would fetch from monitoring system
    %{
      total_executions: :rand.uniform(1000),
      success_rate: 95 + :rand.uniform(5) * 0.8,
      average_duration_ms: 100 + :rand.uniform(400),
      last_24h_executions: :rand.uniform(100),
      error_rate: :rand.uniform(5) * 0.1,
      satisfaction_score: 4.0 + :rand.uniform() * 0.9
    }
  end
end
