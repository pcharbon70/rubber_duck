defmodule RubberDuck.MCP.Server.Resources.SystemState do
  @moduledoc """
  Provides access to RubberDuck system state as MCP resources.
  
  This resource exposes runtime information about the RubberDuck system,
  including active workflows, loaded modules, and system metrics.
  """
  
  use Hermes.Server.Component,
    type: :resource,
    uri: "system://",
    mime_type: "application/json"
  
  alias Hermes.Server.Frame
  
  schema do
    field :component, {:enum, ["overview", "workflows", "modules", "metrics", "config"]},
      description: "System component to inspect",
      default: "overview"
  end
  
  @impl true
  def uri do
    "system://"
  end
  
  @impl true
  def read(%{component: component}, frame) do
    result = case component do
      "overview" -> get_system_overview()
      "workflows" -> get_workflow_info()
      "modules" -> get_module_info()
      "metrics" -> get_system_metrics()
      "config" -> get_system_config()
      _ -> {:error, "Unknown component: #{component}"}
    end
    
    case result do
      {:ok, data} ->
        {:ok, %{
          "content" => Jason.encode!(data, pretty: true),
          "mime_type" => "application/json",
          "component" => component
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "system_error",
          "message" => "Failed to retrieve system state: #{inspect(reason)}"
        }}
    end
  end
  
  @impl true
  def list(frame) do
    components = [
      %{
        "uri" => "system://overview",
        "name" => "System Overview",
        "description" => "General system information and status",
        "mime_type" => "application/json"
      },
      %{
        "uri" => "system://workflows",
        "name" => "Workflow Information",
        "description" => "Active and available workflows",
        "mime_type" => "application/json"
      },
      %{
        "uri" => "system://modules",
        "name" => "Module Information",
        "description" => "Loaded modules and their status",
        "mime_type" => "application/json"
      },
      %{
        "uri" => "system://metrics",
        "name" => "System Metrics",
        "description" => "Performance and resource metrics",
        "mime_type" => "application/json"
      },
      %{
        "uri" => "system://config",
        "name" => "System Configuration",
        "description" => "Current configuration settings",
        "mime_type" => "application/json"
      }
    ]
    
    {:ok, components, frame}
  end
  
  # Private functions
  
  defp get_system_overview do
    {:ok, %{
      "system" => %{
        "name" => "RubberDuck",
        "version" => "0.1.0",
        "elixir_version" => System.version(),
        "otp_version" => :erlang.system_info(:otp_release) |> to_string(),
        "started_at" => get_start_time(),
        "uptime_seconds" => get_uptime()
      },
      "node" => %{
        "name" => node() |> to_string(),
        "cookie" => ((:erlang.get_cookie() |> to_string() |> String.slice(0..7)) <> "..."),
        "alive" => Node.alive?()
      },
      "applications" => %{
        "started" => started_applications(),
        "loaded" => length(:application.loaded_applications())
      }
    }}
  end
  
  defp get_workflow_info do
    # TODO: Integrate with actual workflow system
    {:ok, %{
      "workflows" => %{
        "available" => [
          %{
            "name" => "code_analysis",
            "description" => "Analyzes code structure and quality",
            "status" => "ready"
          },
          %{
            "name" => "test_runner",
            "description" => "Runs project tests",
            "status" => "ready"
          }
        ],
        "active" => [],
        "recent_executions" => []
      }
    }}
  end
  
  defp get_module_info do
    modules = :code.all_loaded()
    |> Enum.filter(fn {mod, _} ->
      mod_str = to_string(mod)
      String.starts_with?(mod_str, "Elixir.RubberDuck")
    end)
    |> Enum.map(fn {mod, _path} ->
      %{
        "name" => inspect(mod),
        "exports" => length(mod.module_info(:exports)),
        "attributes" => get_module_attributes(mod)
      }
    end)
    |> Enum.sort_by(& &1["name"])
    
    {:ok, %{
      "modules" => %{
        "rubber_duck_modules" => modules,
        "total_loaded" => length(:code.all_loaded())
      }
    }}
  end
  
  defp get_system_metrics do
    memory = :erlang.memory()
    schedulers = :erlang.system_info(:schedulers_online)
    
    {:ok, %{
      "metrics" => %{
        "memory" => %{
          "total_mb" => memory[:total] / 1_048_576,
          "processes_mb" => memory[:processes] / 1_048_576,
          "binary_mb" => memory[:binary] / 1_048_576,
          "ets_mb" => memory[:ets] / 1_048_576,
          "atom_mb" => memory[:atom] / 1_048_576
        },
        "processes" => %{
          "count" => length(Process.list()),
          "limit" => :erlang.system_info(:process_limit)
        },
        "schedulers" => %{
          "online" => schedulers,
          "available" => :erlang.system_info(:schedulers)
        },
        "reductions" => :erlang.statistics(:reductions) |> elem(0)
      }
    }}
  end
  
  defp get_system_config do
    # Get non-sensitive configuration
    config = %{
      "environment" => %{
        "mix_env" => Mix.env() |> to_string(),
        "target" => Mix.target() |> to_string()
      },
      "paths" => %{
        "root" => File.cwd!(),
        "priv" => :code.priv_dir(:rubber_duck) |> to_string()
      },
      "features" => %{
        "mcp_client_enabled" => true,
        "mcp_server_enabled" => true,
        "workflow_engine_enabled" => true
      }
    }
    
    {:ok, %{"config" => config}}
  end
  
  defp get_start_time do
    {_, start_time} = :erlang.statistics(:wall_clock)
    DateTime.utc_now()
    |> DateTime.add(-start_time, :millisecond)
    |> DateTime.to_iso8601()
  end
  
  defp get_uptime do
    {_, uptime_ms} = :erlang.statistics(:wall_clock)
    uptime_ms / 1000
  end
  
  defp started_applications do
    Application.started_applications()
    |> Enum.map(fn {name, _desc, _vsn} -> to_string(name) end)
    |> Enum.sort()
  end
  
  defp get_module_attributes(module) do
    try do
      module.module_info(:attributes)
      |> Enum.filter(fn {key, _} ->
        key in [:moduledoc, :behaviour, :derive]
      end)
      |> Enum.into(%{}, fn {key, value} ->
        {to_string(key), inspect(value)}
      end)
    rescue
      _ -> %{}
    end
  end
end