defmodule RubberDuck.Interface.Capabilities do
  @moduledoc """
  Dynamic capability discovery and negotiation system for interface adapters.
  
  This module provides utilities for discovering what features each adapter supports,
  negotiating capabilities between client and server, and validating operations
  against supported capabilities.
  """

  alias RubberDuck.Interface.Behaviour

  @type capability_level :: :basic | :standard | :advanced | :experimental
  @type capability_status :: :available | :deprecated | :disabled | :experimental

  @type capability_info :: %{
    name: Behaviour.capability(),
    level: capability_level(),
    status: capability_status(),
    version: String.t(),
    description: String.t(),
    dependencies: [Behaviour.capability()],
    configuration: map(),
    metadata: map()
  }

  @type capability_set :: %{
    interface: atom(),
    capabilities: [capability_info()],
    version: String.t(),
    timestamp: DateTime.t()
  }

  @type negotiation_result :: %{
    agreed_capabilities: [Behaviour.capability()],
    client_capabilities: [Behaviour.capability()],
    server_capabilities: [Behaviour.capability()],
    negotiation_version: String.t(),
    compatibility_level: :full | :partial | :minimal | :incompatible
  }

  # Core capability categories
  @core_capabilities [
    :chat, :complete, :analyze, :streaming, :file_upload, :file_download,
    :authentication, :session_management, :multi_model, :context_management,
    :history, :export, :health_check, :metrics
  ]

  # Interface-specific capability sets
  @cli_capabilities [
    :chat, :complete, :analyze, :file_upload, :file_download, :session_management,
    :history, :export, :health_check, :interactive_mode, :batch_processing,
    :configuration_management, :plugin_system
  ]

  @tui_capabilities [
    :chat, :complete, :analyze, :streaming, :file_upload, :file_download,
    :session_management, :history, :export, :health_check, :real_time_updates,
    :visual_chat_interface, :conversation_browser, :syntax_highlighting,
    :keyboard_shortcuts, :mouse_navigation, :responsive_layout,
    :status_indicators, :session_tabs, :configuration_interface
  ]

  @web_capabilities [
    :chat, :complete, :analyze, :streaming, :file_upload, :file_download,
    :authentication, :session_management, :multi_model, :context_management,
    :history, :export, :real_time_collaboration, :websocket_support,
    :media_handling, :offline_support
  ]

  @lsp_capabilities [
    :completion, :hover, :signature_help, :definition, :references,
    :document_symbols, :workspace_symbols, :code_actions, :formatting,
    :rename, :diagnostics, :folding_range, :selection_range,
    :semantic_tokens, :inline_values, :workspace_edit
  ]

  @doc """
  Discovers capabilities for a specific adapter.
  
  ## Parameters
  - `adapter_module` - The adapter module or interface type
  - `options` - Discovery options
  
  ## Returns
  - `{:ok, capability_set}` - Discovered capabilities
  - `{:error, reason}` - Discovery failed
  
  ## Examples
  
      iex> Capabilities.discover_capabilities(:cli)
      {:ok, %{
        interface: :cli,
        capabilities: [
          %{name: :chat, level: :standard, status: :available, ...},
          %{name: :file_upload, level: :basic, status: :available, ...}
        ],
        version: "1.0.0",
        timestamp: ~U[...]
      }}
  """
  def discover_capabilities(adapter_module_or_interface, options \\ []) do
    try do
      capability_set = case adapter_module_or_interface do
        module when is_atom(module) ->
          # Check if it's an adapter module with capabilities function
          if Code.ensure_loaded?(module) and function_exported?(module, :capabilities, 0) do
            # Get capabilities from adapter module
            adapter_capabilities = module.capabilities()
            build_capability_set_from_adapter(module, adapter_capabilities, options)
          else
            # Treat as interface type
            case module do
              interface when interface in [:cli, :tui, :web, :lsp] ->
                build_default_capability_set(interface, options)
              _ ->
                {:error, :invalid_adapter_or_interface}
            end
          end
      end
      
      case capability_set do
        {:error, _} = error -> error
        set -> {:ok, set}
      end
    rescue
      error -> {:error, {:discovery_failed, error}}
    end
  end

  @doc """
  Negotiates capabilities between client and server.
  
  ## Parameters
  - `client_capabilities` - List of capabilities the client supports
  - `server_capabilities` - List of capabilities the server supports
  - `options` - Negotiation options
  
  ## Returns
  - `{:ok, negotiation_result}` - Successful negotiation
  - `{:error, reason}` - Negotiation failed
  """
  def negotiate_capabilities(client_capabilities, server_capabilities, options \\ []) do
    strict_mode = Keyword.get(options, :strict_mode, false)
    require_minimum = Keyword.get(options, :require_minimum, [])
    
    try do
      # Find intersection of capabilities
      common_capabilities = find_common_capabilities(client_capabilities, server_capabilities)
      
      # Check minimum requirements
      case validate_minimum_requirements(common_capabilities, require_minimum) do
        :ok ->
          compatibility_level = determine_compatibility_level(
            client_capabilities, 
            server_capabilities, 
            common_capabilities,
            strict_mode
          )
          
          result = %{
            agreed_capabilities: common_capabilities,
            client_capabilities: client_capabilities,
            server_capabilities: server_capabilities,
            negotiation_version: "1.0.0",
            compatibility_level: compatibility_level,
            negotiated_at: DateTime.utc_now()
          }
          
          {:ok, result}
          
        {:error, missing} ->
          {:error, {:minimum_requirements_not_met, missing}}
      end
    rescue
      error -> {:error, {:negotiation_failed, error}}
    end
  end

  @doc """
  Validates if an operation is supported by the given capabilities.
  
  ## Parameters
  - `operation` - Operation to validate
  - `capabilities` - List of available capabilities
  - `options` - Validation options
  
  ## Returns
  - `:ok` - Operation is supported
  - `{:error, reason}` - Operation not supported
  """
  def validate_capability(operation, capabilities, options \\ []) do
    strict = Keyword.get(options, :strict, true)
    
    required_capabilities = map_operation_to_capabilities(operation)
    
    case check_capability_support(required_capabilities, capabilities, strict) do
      :ok -> :ok
      {:missing, missing_caps} -> 
        {:error, {:unsupported_operation, operation, missing_caps}}
    end
  end

  @doc """
  Gets detailed metadata for a specific capability.
  
  ## Parameters
  - `capability` - Capability to get metadata for
  - `interface` - Target interface (optional)
  
  ## Returns
  - `{:ok, capability_info}` - Capability metadata
  - `{:error, reason}` - Capability not found or error
  """
  def capability_metadata(capability, interface \\ nil) do
    case get_capability_definition(capability, interface) do
      nil -> {:error, :capability_not_found}
      definition -> {:ok, definition}
    end
  end

  @doc """
  Merges multiple capability sets into a unified set.
  
  ## Parameters
  - `capability_sets` - List of capability sets to merge
  - `options` - Merge options
  
  ## Returns
  - `{:ok, merged_set}` - Merged capability set
  - `{:error, reason}` - Merge failed
  """
  def merge_capabilities(capability_sets, options \\ []) do
    strategy = Keyword.get(options, :strategy, :union)
    resolve_conflicts = Keyword.get(options, :resolve_conflicts, :latest)
    
    try do
      case strategy do
        :union -> merge_union(capability_sets, resolve_conflicts)
        :intersection -> merge_intersection(capability_sets)
        :weighted -> merge_weighted(capability_sets, options)
        _ -> {:error, :invalid_merge_strategy}
      end
    rescue
      error -> {:error, {:merge_failed, error}}
    end
  end

  @doc """
  Checks if a capability set is compatible with a given interface.
  
  ## Parameters
  - `capability_set` - Capability set to check
  - `interface` - Target interface
  - `options` - Compatibility check options
  
  ## Returns
  - `{:ok, compatibility_info}` - Compatibility check result
  - `{:error, reason}` - Incompatible or error
  """
  def check_compatibility(capability_set, interface, options \\ []) do
    strict = Keyword.get(options, :strict, false)
    
    expected_capabilities = get_interface_capabilities(interface)
    provided_capabilities = extract_capability_names(capability_set)
    
    case analyze_compatibility(expected_capabilities, provided_capabilities, strict) do
      {:compatible, info} -> {:ok, info}
      {:incompatible, reason} -> {:error, {:incompatible, reason}}
    end
  end

  @doc """
  Gets the default capability set for an interface type.
  
  ## Parameters
  - `interface` - Interface type (:cli, :web, :lsp)
  
  ## Returns
  - List of default capabilities for the interface
  """
  def get_interface_capabilities(interface) do
    case interface do
      :cli -> @cli_capabilities
      :tui -> @tui_capabilities
      :web -> @web_capabilities
      :lsp -> @lsp_capabilities
      _ -> @core_capabilities
    end
  end

  @doc """
  Validates capability dependencies and requirements.
  
  ## Parameters
  - `capabilities` - List of capabilities to validate
  - `options` - Validation options
  
  ## Returns
  - `:ok` - All dependencies satisfied
  - `{:error, missing_dependencies}` - Dependencies not met
  """
  def validate_dependencies(capabilities, options \\ []) do
    include_optional = Keyword.get(options, :include_optional, false)
    
    all_requirements = Enum.flat_map(capabilities, fn cap ->
      case get_capability_definition(cap) do
        nil -> []
        definition -> 
          required = Map.get(definition, :dependencies, [])
          optional = if include_optional, do: Map.get(definition, :optional_dependencies, []), else: []
          required ++ optional
      end
    end)
    |> Enum.uniq()
    
    missing = Enum.reject(all_requirements, &(&1 in capabilities))
    
    case missing do
      [] -> :ok
      missing_deps -> {:error, {:missing_dependencies, missing_deps}}
    end
  end

  # Private functions

  defp build_capability_set_from_adapter(module, adapter_capabilities, options) do
    interface = infer_interface_from_module(module)
    version = Keyword.get(options, :version, "1.0.0")
    
    capabilities = Enum.map(adapter_capabilities, fn cap ->
      build_capability_info(cap, interface, options)
    end)
    
    %{
      interface: interface,
      capabilities: capabilities,
      version: version,
      timestamp: DateTime.utc_now(),
      source: :adapter,
      module: module
    }
  end

  defp build_default_capability_set(interface, options) do
    default_caps = get_interface_capabilities(interface)
    version = Keyword.get(options, :version, "1.0.0")
    
    capabilities = Enum.map(default_caps, fn cap ->
      build_capability_info(cap, interface, options)
    end)
    
    %{
      interface: interface,
      capabilities: capabilities,
      version: version,
      timestamp: DateTime.utc_now(),
      source: :default
    }
  end

  defp build_capability_info(capability, interface, options) do
    definition = get_capability_definition(capability, interface)
    
    %{
      name: capability,
      level: Map.get(definition, :level, :standard),
      status: Map.get(definition, :status, :available),
      version: Map.get(definition, :version, "1.0.0"),
      description: Map.get(definition, :description, ""),
      dependencies: Map.get(definition, :dependencies, []),
      configuration: Keyword.get(options, :configuration, %{}),
      metadata: Map.get(definition, :metadata, %{})
    }
  end

  defp get_capability_definition(capability, interface \\ nil) do
    base_definitions = %{
      # Core capabilities
      chat: %{
        level: :standard,
        status: :available,
        version: "1.0.0",
        description: "Text-based conversational interface",
        dependencies: [],
        metadata: %{category: :core, priority: :high}
      },
      complete: %{
        level: :standard,
        status: :available,
        version: "1.0.0",
        description: "Text completion and generation",
        dependencies: [],
        metadata: %{category: :core, priority: :high}
      },
      analyze: %{
        level: :advanced,
        status: :available,
        version: "1.0.0",
        description: "Content analysis and insights",
        dependencies: [],
        metadata: %{category: :advanced, priority: :medium}
      },
      streaming: %{
        level: :advanced,
        status: :available,
        version: "1.0.0",
        description: "Real-time streaming responses",
        dependencies: [],
        metadata: %{category: :advanced, priority: :medium}
      },
      file_upload: %{
        level: :basic,
        status: :available,
        version: "1.0.0",
        description: "File upload and processing",
        dependencies: [],
        metadata: %{category: :io, priority: :medium}
      },
      file_download: %{
        level: :basic,
        status: :available,
        version: "1.0.0",
        description: "File download and export",
        dependencies: [],
        metadata: %{category: :io, priority: :medium}
      },
      authentication: %{
        level: :standard,
        status: :available,
        version: "1.0.0",
        description: "User authentication and authorization",
        dependencies: [],
        metadata: %{category: :security, priority: :high}
      },
      session_management: %{
        level: :standard,
        status: :available,
        version: "1.0.0",
        description: "Session state management",
        dependencies: [:authentication],
        metadata: %{category: :state, priority: :high}
      },
      multi_model: %{
        level: :advanced,
        status: :available,
        version: "1.0.0",
        description: "Multiple AI model support",
        dependencies: [],
        metadata: %{category: :ai, priority: :medium}
      },
      context_management: %{
        level: :advanced,
        status: :available,
        version: "1.0.0",
        description: "Context and memory management",
        dependencies: [:session_management],
        metadata: %{category: :ai, priority: :high}
      },
      history: %{
        level: :standard,
        status: :available,
        version: "1.0.0",
        description: "Conversation and operation history",
        dependencies: [:session_management],
        metadata: %{category: :data, priority: :medium}
      },
      export: %{
        level: :basic,
        status: :available,
        version: "1.0.0",
        description: "Data export functionality",
        dependencies: [],
        metadata: %{category: :io, priority: :low}
      },
      health_check: %{
        level: :basic,
        status: :available,
        version: "1.0.0",
        description: "System health monitoring",
        dependencies: [],
        metadata: %{category: :monitoring, priority: :high}
      },
      metrics: %{
        level: :advanced,
        status: :available,
        version: "1.0.0",
        description: "Performance and usage metrics",
        dependencies: [],
        metadata: %{category: :monitoring, priority: :medium}
      }
    }
    
    # Add interface-specific definitions
    interface_definitions = case interface do
      :cli -> %{
        interactive_mode: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Interactive command-line mode",
          dependencies: [],
          metadata: %{category: :cli, priority: :medium}
        },
        batch_processing: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Batch processing mode",
          dependencies: [],
          metadata: %{category: :cli, priority: :low}
        }
      }
      :tui -> %{
        visual_chat_interface: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Visual chat interface with panels and windows",
          dependencies: [:chat],
          metadata: %{category: :tui, priority: :high}
        },
        conversation_browser: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Browse and search conversation history",
          dependencies: [:history, :session_management],
          metadata: %{category: :tui, priority: :medium}
        },
        syntax_highlighting: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Syntax highlighting for code blocks",
          dependencies: [],
          metadata: %{category: :tui, priority: :medium}
        },
        keyboard_shortcuts: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Keyboard navigation and shortcuts",
          dependencies: [],
          metadata: %{category: :tui, priority: :high}
        },
        mouse_navigation: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Mouse support for navigation and interaction",
          dependencies: [],
          metadata: %{category: :tui, priority: :medium}
        },
        responsive_layout: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Layout adapts to terminal size changes",
          dependencies: [],
          metadata: %{category: :tui, priority: :medium}
        },
        status_indicators: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Visual indicators for connection, typing, processing",
          dependencies: [],
          metadata: %{category: :tui, priority: :high}
        },
        session_tabs: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Multiple session management with tabs",
          dependencies: [:session_management],
          metadata: %{category: :tui, priority: :medium}
        },
        configuration_interface: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Interactive configuration and preferences",
          dependencies: [],
          metadata: %{category: :tui, priority: :low}
        },
        real_time_updates: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Real-time updates and streaming responses",
          dependencies: [:streaming],
          metadata: %{category: :tui, priority: :high}
        }
      }
      :web -> %{
        websocket_support: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "WebSocket real-time communication",
          dependencies: [:streaming],
          metadata: %{category: :web, priority: :medium}
        },
        real_time_collaboration: %{
          level: :experimental,
          status: :experimental,
          version: "0.1.0",
          description: "Real-time collaborative features",
          dependencies: [:websocket_support, :session_management],
          metadata: %{category: :web, priority: :low}
        }
      }
      :lsp -> %{
        completion: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Code completion",
          dependencies: [],
          metadata: %{category: :lsp, priority: :high}
        },
        hover: %{
          level: :standard,
          status: :available,
          version: "1.0.0",
          description: "Hover information",
          dependencies: [],
          metadata: %{category: :lsp, priority: :medium}
        },
        diagnostics: %{
          level: :advanced,
          status: :available,
          version: "1.0.0",
          description: "Code diagnostics and errors",
          dependencies: [],
          metadata: %{category: :lsp, priority: :high}
        }
      }
      _ -> %{}
    end
    
    all_definitions = Map.merge(base_definitions, interface_definitions)
    Map.get(all_definitions, capability)
  end

  defp find_common_capabilities(client_caps, server_caps) do
    # Simple intersection for now
    client_set = MapSet.new(extract_capability_names(client_caps))
    server_set = MapSet.new(extract_capability_names(server_caps))
    
    MapSet.intersection(client_set, server_set)
    |> MapSet.to_list()
  end

  defp extract_capability_names(capabilities) when is_list(capabilities) do
    Enum.map(capabilities, fn
      cap when is_atom(cap) -> cap
      %{name: name} -> name
      cap when is_map(cap) -> Map.get(cap, :name, cap)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_capability_names(capability_set) when is_map(capability_set) do
    capability_set
    |> Map.get(:capabilities, [])
    |> extract_capability_names()
  end

  defp validate_minimum_requirements(capabilities, required) do
    missing = Enum.reject(required, &(&1 in capabilities))
    
    case missing do
      [] -> :ok
      missing -> {:error, missing}
    end
  end

  defp determine_compatibility_level(client_caps, server_caps, common_caps, strict_mode) do
    client_count = length(extract_capability_names(client_caps))
    server_count = length(extract_capability_names(server_caps))
    common_count = length(common_caps)
    
    if strict_mode do
      if common_count == client_count and common_count == server_count do
        :full
      else
        :incompatible
      end
    else
      cond do
        common_count == 0 -> :incompatible
        common_count >= min(client_count, server_count) * 0.9 -> :full
        common_count >= min(client_count, server_count) * 0.6 -> :partial
        common_count >= min(client_count, server_count) * 0.3 -> :minimal
        true -> :incompatible
      end
    end
  end

  defp map_operation_to_capabilities(operation) do
    case operation do
      :chat -> [:chat]
      :complete -> [:complete]
      :analyze -> [:analyze]
      :stream_chat -> [:chat, :streaming]
      :upload_file -> [:file_upload]
      :download_file -> [:file_download]
      :authenticate -> [:authentication]
      :get_history -> [:history, :session_management]
      :export_data -> [:export]
      _ -> []
    end
  end

  defp check_capability_support(required, available, strict) do
    available_names = extract_capability_names(available)
    missing = Enum.reject(required, &(&1 in available_names))
    
    case {missing, strict} do
      {[], _} -> :ok
      {missing, true} -> {:missing, missing}
      {missing, false} when length(missing) < length(required) -> :ok
      {missing, false} -> {:missing, missing}
    end
  end

  defp infer_interface_from_module(module) do
    module_name = Module.split(module) |> List.last() |> String.downcase()
    
    cond do
      String.contains?(module_name, "tui") -> :tui
      String.contains?(module_name, "terminal") -> :tui
      String.contains?(module_name, "cli") -> :cli
      String.contains?(module_name, "web") -> :web
      String.contains?(module_name, "lsp") -> :lsp
      String.contains?(module_name, "http") -> :web
      String.contains?(module_name, "console") -> :cli
      true -> :generic
    end
  end

  defp merge_union(capability_sets, resolve_conflicts) do
    all_capabilities = Enum.flat_map(capability_sets, fn set ->
      Map.get(set, :capabilities, [])
    end)
    
    # Group by capability name and resolve conflicts
    grouped = Enum.group_by(all_capabilities, &Map.get(&1, :name))
    
    resolved = Enum.map(grouped, fn {_name, capabilities} ->
      case capabilities do
        [single] -> single
        multiple -> resolve_capability_conflict(multiple, resolve_conflicts)
      end
    end)
    
    merged_set = %{
      interface: :merged,
      capabilities: resolved,
      version: "1.0.0",
      timestamp: DateTime.utc_now(),
      source: :merged,
      merge_strategy: :union
    }
    
    {:ok, merged_set}
  end

  defp merge_intersection(capability_sets) do
    if Enum.empty?(capability_sets) do
      {:error, :no_capability_sets}
    else
      [first | rest] = Enum.map(capability_sets, fn set ->
        set
        |> Map.get(:capabilities, [])
        |> Enum.map(&Map.get(&1, :name))
        |> MapSet.new()
      end)
      
      common_names = Enum.reduce(rest, first, &MapSet.intersection/2)
      
      # Take capability definitions from first set
      first_set = List.first(capability_sets)
      common_capabilities = first_set
      |> Map.get(:capabilities, [])
      |> Enum.filter(&(Map.get(&1, :name) in common_names))
      
      merged_set = %{
        interface: :merged,
        capabilities: common_capabilities,
        version: "1.0.0",
        timestamp: DateTime.utc_now(),
        source: :merged,
        merge_strategy: :intersection
      }
      
      {:ok, merged_set}
    end
  end

  defp merge_weighted(capability_sets, options) do
    _weights = Keyword.get(options, :weights, [])
    
    # For now, fall back to union merge
    # In a full implementation, this would apply weights to capability selection
    merge_union(capability_sets, :latest)
  end

  defp resolve_capability_conflict(capabilities, strategy) do
    case strategy do
      :latest -> 
        Enum.max_by(capabilities, &Map.get(&1, :version, "0.0.0"))
      :highest_level ->
        level_order = %{basic: 1, standard: 2, advanced: 3, experimental: 4}
        Enum.max_by(capabilities, &Map.get(level_order, Map.get(&1, :level, :basic), 1))
      :first ->
        List.first(capabilities)
      _ ->
        List.first(capabilities)
    end
  end

  defp analyze_compatibility(expected, provided, strict) do
    expected_set = MapSet.new(expected)
    provided_set = MapSet.new(provided)
    
    intersection = MapSet.intersection(expected_set, provided_set)
    missing = MapSet.difference(expected_set, provided_set)
    extra = MapSet.difference(provided_set, expected_set)
    
    coverage = MapSet.size(intersection) / max(MapSet.size(expected_set), 1)
    
    compatibility_info = %{
      coverage: coverage,
      missing_capabilities: MapSet.to_list(missing),
      extra_capabilities: MapSet.to_list(extra),
      common_capabilities: MapSet.to_list(intersection),
      compatibility_score: calculate_compatibility_score(coverage, missing, extra, strict)
    }
    
    if strict and MapSet.size(missing) > 0 do
      {:incompatible, :missing_required_capabilities}
    else
      case coverage do
        c when c >= 0.9 -> {:compatible, Map.put(compatibility_info, :level, :full)}
        c when c >= 0.7 -> {:compatible, Map.put(compatibility_info, :level, :high)}
        c when c >= 0.5 -> {:compatible, Map.put(compatibility_info, :level, :partial)}
        c when c >= 0.3 -> {:compatible, Map.put(compatibility_info, :level, :minimal)}
        _ -> {:incompatible, :insufficient_capability_coverage}
      end
    end
  end

  defp calculate_compatibility_score(coverage, missing, extra, strict) do
    base_score = coverage * 100
    
    # Penalize missing capabilities more in strict mode
    missing_penalty = if strict, do: MapSet.size(missing) * 10, else: MapSet.size(missing) * 5
    
    # Extra capabilities are generally good, but might indicate version mismatch
    extra_bonus = min(MapSet.size(extra) * 2, 10)
    
    max(0, base_score - missing_penalty + extra_bonus)
  end
end