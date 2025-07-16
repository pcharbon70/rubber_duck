defmodule RubberDuck.MCP.Integration.CLI do
  @moduledoc """
  CLI integration for MCP commands.
  
  This module adds MCP-specific commands to RubberDuck's CLI,
  enabling command-line interaction with MCP tools and resources.
  """
  
  alias RubberDuck.MCP.{Client, Registry}
  alias RubberDuck.MCP.Registry.{Composition, Metrics}
  
  @doc """
  Lists available MCP tools.
  """
  def list_tools(opts \\ []) do
    case Registry.list_tools(opts) do
      {:ok, tools} ->
        if opts[:format] == :json do
          tools
          |> Enum.map(&format_tool_json/1)
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_tools_table(tools)
        end
        
      {:error, reason} ->
        IO.puts("Error listing tools: #{inspect(reason)}")
    end
  end
  
  @doc """
  Shows detailed information about a specific tool.
  """
  def show_tool(tool_name, opts \\ []) do
    case Registry.get_tool(tool_name) do
      {:ok, tool} ->
        if opts[:format] == :json do
          tool
          |> format_tool_json()
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_tool_details(tool)
        end
        
      {:error, :not_found} ->
        IO.puts("Tool not found: #{tool_name}")
        
      {:error, reason} ->
        IO.puts("Error retrieving tool: #{inspect(reason)}")
    end
  end
  
  @doc """
  Executes an MCP tool from the command line.
  """
  def execute_tool(tool_name, params_json, opts \\ []) do
    with {:ok, params} <- Jason.decode(params_json),
         {:ok, result} <- Registry.execute_tool(tool_name, params) do
      
      if opts[:format] == :json do
        result
        |> Jason.encode!(pretty: true)
        |> IO.puts()
      else
        format_execution_result(result)
      end
      
    else
      {:error, %Jason.DecodeError{}} ->
        IO.puts("Invalid JSON parameters")
        
      {:error, reason} ->
        IO.puts("Execution failed: #{inspect(reason)}")
    end
  end
  
  @doc """
  Lists MCP tool metrics.
  """
  def show_metrics(tool_name \\ nil, opts \\ []) do
    if tool_name do
      show_tool_metrics(tool_name, opts)
    else
      show_all_metrics(opts)
    end
  end
  
  @doc """
  Searches for MCP tools.
  """
  def search_tools(query, opts \\ []) do
    case Registry.search_tools(query, opts) do
      {:ok, tools} ->
        if opts[:format] == :json do
          tools
          |> Enum.map(&format_tool_json/1)
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_search_results(tools, query)
        end
        
      {:error, reason} ->
        IO.puts("Search failed: #{inspect(reason)}")
    end
  end
  
  @doc """
  Lists available MCP clients.
  """
  def list_clients(opts \\ []) do
    clients = Registry.list_clients()
    
    if opts[:format] == :json do
      clients
      |> Enum.map(&format_client_json/1)
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      format_clients_table(clients)
    end
  end
  
  @doc """
  Shows MCP client status.
  """
  def show_client(client_name, opts \\ []) do
    case Registry.get_client(client_name) do
      {:ok, client} ->
        if opts[:format] == :json do
          client
          |> format_client_json()
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_client_details(client)
        end
        
      {:error, :not_found} ->
        IO.puts("Client not found: #{client_name}")
        
      {:error, reason} ->
        IO.puts("Error retrieving client: #{inspect(reason)}")
    end
  end
  
  @doc """
  Lists tool compositions.
  """
  def list_compositions(opts \\ []) do
    case Registry.list_compositions(opts) do
      {:ok, compositions} ->
        if opts[:format] == :json do
          compositions
          |> Enum.map(&format_composition_json/1)
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_compositions_table(compositions)
        end
        
      {:error, reason} ->
        IO.puts("Error listing compositions: #{inspect(reason)}")
    end
  end
  
  @doc """
  Executes a tool composition.
  """
  def execute_composition(composition_id, input_json, opts \\ []) do
    with {:ok, composition} <- Registry.get_composition(composition_id),
         {:ok, input} <- Jason.decode(input_json),
         {:ok, result} <- Composition.execute(composition, input, opts) do
      
      if opts[:format] == :json do
        result
        |> Jason.encode!(pretty: true)
        |> IO.puts()
      else
        format_composition_result(result)
      end
      
    else
      {:error, %Jason.DecodeError{}} ->
        IO.puts("Invalid JSON input")
        
      {:error, reason} ->
        IO.puts("Composition execution failed: #{inspect(reason)}")
    end
  end
  
  @doc """
  Shows system status including MCP integration.
  """
  def show_status(opts \\ []) do
    status = %{
      registry_status: get_registry_status(),
      client_status: get_client_status(),
      tool_status: get_tool_status(),
      composition_status: get_composition_status()
    }
    
    if opts[:format] == :json do
      status
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      format_status_display(status)
    end
  end
  
  @doc """
  Generates tool composition based on description.
  """
  def suggest_composition(description, opts \\ []) do
    case suggest_tools_for_task(description, opts) do
      {:ok, suggestions} ->
        if opts[:format] == :json do
          suggestions
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          format_composition_suggestions(suggestions)
        end
        
      {:error, reason} ->
        IO.puts("Failed to generate suggestions: #{inspect(reason)}")
    end
  end
  
  # Private functions
  
  defp format_tools_table(tools) do
    IO.puts("\n#{String.pad_trailing("Tool Name", 25)} #{String.pad_trailing("Category", 15)} #{String.pad_trailing("Description", 50)} Quality")
    IO.puts(String.duplicate("-", 100))
    
    Enum.each(tools, fn tool ->
      quality = case Registry.get_metrics(tool.module) do
        {:ok, metrics} -> 
          score = Metrics.quality_score(metrics)
          "#{Float.round(score, 1)}%"
        _ -> "N/A"
      end
      
      name = String.pad_trailing(tool.name, 25)
      category = String.pad_trailing(to_string(tool.category), 15)
      description = String.pad_trailing(String.slice(tool.description, 0..47), 50)
      
      IO.puts("#{name} #{category} #{description} #{quality}")
    end)
    
    IO.puts("\nTotal: #{length(tools)} tools")
  end
  
  defp format_tool_details(tool) do
    IO.puts("\n=== Tool Details ===")
    IO.puts("Name: #{tool.name}")
    IO.puts("Category: #{tool.category}")
    IO.puts("Description: #{tool.description}")
    IO.puts("Tags: #{Enum.join(tool.tags, ", ")}")
    IO.puts("Capabilities: #{Enum.join(tool.capabilities, ", ")}")
    IO.puts("Version: #{tool.version}")
    IO.puts("Source: #{tool.source}")
    IO.puts("Registered: #{tool.registered_at}")
    
    if not Enum.empty?(tool.examples) do
      IO.puts("\nExamples:")
      Enum.each(tool.examples, fn example ->
        IO.puts("  • #{example.description}")
        IO.puts("    #{Jason.encode!(example.params)}")
      end)
    end
    
    # Show metrics if available
    case Registry.get_metrics(tool.module) do
      {:ok, metrics} ->
        IO.puts("\nMetrics:")
        summary = Metrics.summary(metrics)
        IO.puts("  Total Executions: #{summary.total_executions}")
        IO.puts("  Success Rate: #{summary.success_rate}%")
        IO.puts("  Average Latency: #{summary.average_latency_ms}ms")
        IO.puts("  Quality Score: #{summary.quality_score}")
        
      _ ->
        IO.puts("\nNo metrics available")
    end
  end
  
  defp format_tool_json(tool) do
    base = %{
      name: tool.name,
      category: tool.category,
      description: tool.description,
      tags: tool.tags,
      capabilities: tool.capabilities,
      version: tool.version,
      source: tool.source,
      registered_at: tool.registered_at,
      examples: tool.examples
    }
    
    # Add metrics if available
    case Registry.get_metrics(tool.module) do
      {:ok, metrics} ->
        Map.put(base, :metrics, Metrics.summary(metrics))
      _ ->
        base
    end
  end
  
  defp format_execution_result(result) do
    IO.puts("\n=== Execution Result ===")
    IO.puts("Status: #{result["status"] || "completed"}")
    
    if result["execution_time_ms"] do
      IO.puts("Execution Time: #{result["execution_time_ms"]}ms")
    end
    
    if result["result"] do
      IO.puts("Result:")
      IO.puts(Jason.encode!(result["result"], pretty: true))
    end
  end
  
  defp show_tool_metrics(tool_name, opts) do
    case Registry.get_metrics(tool_name) do
      {:ok, metrics} ->
        summary = Metrics.summary(metrics)
        
        if opts[:format] == :json do
          summary
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          IO.puts("\n=== Tool Metrics: #{tool_name} ===")
          IO.puts("Total Executions: #{summary.total_executions}")
          IO.puts("Success Rate: #{summary.success_rate}%")
          IO.puts("Average Latency: #{summary.average_latency_ms}ms")
          IO.puts("Min Latency: #{summary.min_latency_ms}ms")
          IO.puts("Max Latency: #{summary.max_latency_ms}ms")
          IO.puts("Quality Score: #{summary.quality_score}")
          IO.puts("Last Execution: #{summary.last_execution}")
          
          if not Enum.empty?(summary.error_distribution) do
            IO.puts("\nError Distribution:")
            Enum.each(summary.error_distribution, fn {error, count} ->
              IO.puts("  #{error}: #{count}")
            end)
          end
        end
        
      {:error, :not_found} ->
        IO.puts("Tool not found: #{tool_name}")
        
      {:error, reason} ->
        IO.puts("Error retrieving metrics: #{inspect(reason)}")
    end
  end
  
  defp show_all_metrics(opts) do
    case Registry.list_tools() do
      {:ok, tools} ->
        metrics_data = Enum.map(tools, fn tool ->
          case Registry.get_metrics(tool.module) do
            {:ok, metrics} ->
              summary = Metrics.summary(metrics)
              Map.put(summary, :tool_name, tool.name)
            _ ->
              %{tool_name: tool.name, total_executions: 0}
          end
        end)
        |> Enum.sort_by(& &1.total_executions, :desc)
        
        if opts[:format] == :json do
          metrics_data
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          IO.puts("\n#{String.pad_trailing("Tool Name", 25)} #{String.pad_trailing("Executions", 12)} #{String.pad_trailing("Success Rate", 13)} #{String.pad_trailing("Avg Latency", 12)} Quality")
          IO.puts(String.duplicate("-", 70))
          
          Enum.each(metrics_data, fn metrics ->
            name = String.pad_trailing(metrics.tool_name, 25)
            executions = String.pad_trailing(to_string(metrics.total_executions || 0), 12)
            success_rate = String.pad_trailing("#{metrics.success_rate || 0}%", 13)
            avg_latency = String.pad_trailing("#{metrics.average_latency_ms || 0}ms", 12)
            quality = "#{metrics.quality_score || 0}"
            
            IO.puts("#{name} #{executions} #{success_rate} #{avg_latency} #{quality}")
          end)
        end
        
      {:error, reason} ->
        IO.puts("Error listing tools: #{inspect(reason)}")
    end
  end
  
  defp format_search_results(tools, query) do
    IO.puts("\nSearch results for '#{query}':")
    IO.puts(String.duplicate("-", 50))
    
    if Enum.empty?(tools) do
      IO.puts("No tools found matching '#{query}'")
    else
      Enum.each(tools, fn tool ->
        IO.puts("• #{tool.name} (#{tool.category})")
        IO.puts("  #{tool.description}")
        IO.puts("  Tags: #{Enum.join(tool.tags, ", ")}")
        IO.puts("")
      end)
      
      IO.puts("Found #{length(tools)} tools")
    end
  end
  
  defp format_clients_table(clients) do
    IO.puts("\n#{String.pad_trailing("Client Name", 20)} #{String.pad_trailing("Status", 12)} #{String.pad_trailing("Capabilities", 30)} Connected")
    IO.puts(String.duplicate("-", 80))
    
    Enum.each(clients, fn client ->
      name = String.pad_trailing(client.name, 20)
      status = String.pad_trailing(to_string(client.status), 12)
      capabilities = String.pad_trailing(Enum.join(client.capabilities, ", "), 30)
      connected = client.connected_at
      
      IO.puts("#{name} #{status} #{capabilities} #{connected}")
    end)
    
    IO.puts("\nTotal: #{length(clients)} clients")
  end
  
  defp format_client_details(client) do
    IO.puts("\n=== Client Details ===")
    IO.puts("Name: #{client.name}")
    IO.puts("Status: #{client.status}")
    IO.puts("Capabilities: #{Enum.join(client.capabilities, ", ")}")
    IO.puts("Connected: #{client.connected_at}")
    IO.puts("Transport: #{client.transport}")
    
    if client.tools do
      IO.puts("\nAvailable Tools: #{length(client.tools)}")
      Enum.each(client.tools, fn tool ->
        IO.puts("  • #{tool.name}: #{tool.description}")
      end)
    end
    
    if client.resources do
      IO.puts("\nAvailable Resources: #{length(client.resources)}")
      Enum.each(client.resources, fn resource ->
        IO.puts("  • #{resource.name}: #{resource.description}")
      end)
    end
  end
  
  defp format_client_json(client) do
    %{
      name: client.name,
      status: client.status,
      capabilities: client.capabilities,
      connected_at: client.connected_at,
      transport: client.transport,
      tools: client.tools || [],
      resources: client.resources || []
    }
  end
  
  defp format_compositions_table(compositions) do
    IO.puts("\n#{String.pad_trailing("Composition ID", 20)} #{String.pad_trailing("Name", 25)} #{String.pad_trailing("Type", 12)} Tools")
    IO.puts(String.duplicate("-", 70))
    
    Enum.each(compositions, fn composition ->
      id = String.pad_trailing(String.slice(composition.id, 0..17), 20)
      name = String.pad_trailing(composition.name, 25)
      type = String.pad_trailing(to_string(composition.type), 12)
      tools = length(composition.tools)
      
      IO.puts("#{id} #{name} #{type} #{tools}")
    end)
    
    IO.puts("\nTotal: #{length(compositions)} compositions")
  end
  
  defp format_composition_json(composition) do
    %{
      id: composition.id,
      name: composition.name,
      description: composition.description,
      type: composition.type,
      tools: composition.tools,
      created_at: composition.created_at,
      metadata: composition.metadata
    }
  end
  
  defp format_composition_result(result) do
    IO.puts("\n=== Composition Result ===")
    IO.puts("Composition ID: #{result.composition_id}")
    IO.puts("Status: #{result.status}")
    IO.puts("Execution Time: #{result.execution_time_ms}ms")
    IO.puts("Results: #{length(result.results)}")
    
    if not Enum.empty?(result.errors) do
      IO.puts("Errors: #{length(result.errors)}")
      Enum.each(result.errors, fn error ->
        IO.puts("  • #{inspect(error)}")
      end)
    end
    
    if result.final_output do
      IO.puts("\nFinal Output:")
      IO.puts(Jason.encode!(result.final_output, pretty: true))
    end
  end
  
  defp get_registry_status do
    %{
      running: Registry.running?(),
      tool_count: case Registry.list_tools() do
        {:ok, tools} -> length(tools)
        _ -> 0
      end,
      composition_count: case Registry.list_compositions() do
        {:ok, compositions} -> length(compositions)
        _ -> 0
      end
    }
  end
  
  defp get_client_status do
    clients = Registry.list_clients()
    %{
      total_clients: length(clients),
      connected_clients: Enum.count(clients, fn client -> client.status == :connected end),
      client_names: Enum.map(clients, & &1.name)
    }
  end
  
  defp get_tool_status do
    case Registry.list_tools() do
      {:ok, tools} ->
        %{
          total_tools: length(tools),
          categories: tools |> Enum.group_by(& &1.category) |> Map.keys(),
          avg_quality: tools 
          |> Enum.map(fn tool ->
            case Registry.get_metrics(tool.module) do
              {:ok, metrics} -> Metrics.quality_score(metrics)
              _ -> 0
            end
          end)
          |> Enum.sum() / length(tools)
        }
      _ ->
        %{total_tools: 0, categories: [], avg_quality: 0}
    end
  end
  
  defp get_composition_status do
    case Registry.list_compositions() do
      {:ok, compositions} ->
        %{
          total_compositions: length(compositions),
          composition_types: compositions |> Enum.group_by(& &1.type) |> Map.keys()
        }
      _ ->
        %{total_compositions: 0, composition_types: []}
    end
  end
  
  defp format_status_display(status) do
    IO.puts("\n=== MCP System Status ===")
    IO.puts("Registry: #{if status.registry_status.running, do: "Running", else: "Stopped"}")
    IO.puts("Tools: #{status.registry_status.tool_count}")
    IO.puts("Compositions: #{status.registry_status.composition_count}")
    
    IO.puts("\nClients:")
    IO.puts("  Total: #{status.client_status.total_clients}")
    IO.puts("  Connected: #{status.client_status.connected_clients}")
    IO.puts("  Names: #{Enum.join(status.client_status.client_names, ", ")}")
    
    IO.puts("\nTools:")
    IO.puts("  Total: #{status.tool_status.total_tools}")
    IO.puts("  Categories: #{Enum.join(status.tool_status.categories, ", ")}")
    IO.puts("  Average Quality: #{Float.round(status.tool_status.avg_quality, 1)}%")
    
    IO.puts("\nCompositions:")
    IO.puts("  Total: #{status.composition_status.total_compositions}")
    IO.puts("  Types: #{Enum.join(status.composition_status.composition_types, ", ")}")
  end
  
  defp suggest_tools_for_task(description, opts) do
    # Simple keyword-based tool suggestion
    keywords = description
    |> String.downcase()
    |> String.split()
    |> Enum.filter(fn word -> String.length(word) > 3 end)
    
    # Search for tools matching keywords
    case Registry.list_tools() do
      {:ok, tools} ->
        suggestions = tools
        |> Enum.filter(fn tool ->
          tool_text = "#{tool.name} #{tool.description} #{Enum.join(tool.tags, " ")}"
          |> String.downcase()
          
          Enum.any?(keywords, fn keyword ->
            String.contains?(tool_text, keyword)
          end)
        end)
        |> Enum.take(opts[:limit] || 5)
        
        {:ok, %{
          description: description,
          suggested_tools: suggestions,
          suggested_composition: generate_composition_suggestion(suggestions)
        }}
        
      error -> error
    end
  end
  
  defp generate_composition_suggestion(tools) do
    if length(tools) > 1 do
      %{
        name: "Generated Composition",
        type: :sequential,
        tools: Enum.map(tools, fn tool -> %{tool: tool.name, params: %{}} end)
      }
    else
      nil
    end
  end
  
  defp format_composition_suggestions(suggestions) do
    IO.puts("\nTask: #{suggestions.description}")
    IO.puts(String.duplicate("-", 50))
    
    if Enum.empty?(suggestions.suggested_tools) do
      IO.puts("No tools found for this task")
    else
      IO.puts("Suggested Tools:")
      Enum.each(suggestions.suggested_tools, fn tool ->
        IO.puts("• #{tool.name} - #{tool.description}")
      end)
      
      if suggestions.suggested_composition do
        comp = suggestions.suggested_composition
        IO.puts("\nSuggested Composition (#{comp.type}):")
        Enum.each(comp.tools, fn tool_spec ->
          IO.puts("  #{tool_spec.tool}")
        end)
      end
    end
  end
end