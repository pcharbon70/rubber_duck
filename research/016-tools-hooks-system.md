# Designing a Hooks System for RubberDuck: A Comprehensive Implementation Guide

## Executive Summary

Based on extensive research of Claude's hooks system and Elixir patterns, I've designed a **project-aware** hooks architecture that maintains exact JSON format compatibility with Claude while leveraging Elixir's strengths. The key enhancement is that hooks are scoped per-project, with configurations loaded from:

1. **Project-specific hooks** in `<project>/.rubber_duck/settings.json` (version controlled)
2. **Local overrides** in `<project>/.rubber_duck/settings.local.json` (gitignored) 
3. **Global user hooks** in `~/.rubber_duck/settings.json` (applied to all projects)

This design ensures that:
- Each project can have its own hooks configuration
- Hooks execute with the project directory as the working directory
- Teams can share project-specific hooks via version control
- Individual developers can add personal hooks without affecting others

Since the specific RubberDuck Phase 9 implementation details weren't publicly available, this design provides a flexible foundation that can integrate with any existing tool system architecture. The solution uses Elixir behaviors for extensibility, GenServers for state management, and pattern matching for efficient dispatch.

## 1. Core Architecture Design

### Hook System Components

The hooks system is project-aware and consists of five main components that work together to provide Claude-compatible functionality in Elixir:

```elixir
defmodule RubberDuck.Hooks.System do
  @moduledoc """
  Main entry point for the project-aware hooks system, maintaining compatibility
  with Claude's JSON format while leveraging Elixir patterns
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :project_configs,  # Map of project_id => configuration
    :event_bus,
    :matcher_registry,
    :executor,
    :cache
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def execute_hooks(project_id, event_name, data) do
    GenServer.call(__MODULE__, {:execute_hooks, project_id, event_name, data})
  end
  
  def load_project_hooks(project_id) do
    GenServer.call(__MODULE__, {:load_project_hooks, project_id})
  end
  
  def unload_project_hooks(project_id) do
    GenServer.call(__MODULE__, {:unload_project_hooks, project_id})
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      project_configs: %{},
      event_bus: RubberDuck.Hooks.EventBus,
      matcher_registry: RubberDuck.Hooks.MatcherRegistry,
      executor: RubberDuck.Hooks.Executor,
      cache: RubberDuck.Hooks.Cache
    }
    {:ok, state}
  end
  
  @impl true
  def handle_call({:load_project_hooks, project_id}, _from, state) do
    case RubberDuck.Hooks.ConfigLoader.load_configuration(project_id) do
      {:ok, config} ->
        new_configs = Map.put(state.project_configs, project_id, config)
        {:reply, :ok, %{state | project_configs: new_configs}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:execute_hooks, project_id, event_name, data}, _from, state) do
    config = Map.get(state.project_configs, project_id)
    
    if config do
      context = Map.merge(data, %{
        project_id: project_id,
        config: config,
        project_root: get_project_root(project_id)
      })
      
      result = state.executor.execute_hooks(event_name, context)
      {:reply, result, state}
    else
      {:reply, {:error, :project_not_loaded}, state}
    end
  end
  
  defp get_project_root(project_id) do
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} -> project.root_path
      _ -> nil
    end
  end
end
```

### Configuration Loader

The configuration system is project-aware and reads from project-specific `.rubber_duck` directories:

```elixir
defmodule RubberDuck.Hooks.ConfigLoader do
  @doc """
  Loads hook configurations from project-specific .rubber_duck directory hierarchy,
  maintaining Claude's JSON format exactly
  """
  
  @global_config_path "~/.rubber_duck/settings.json"
  
  def load_configuration(project_id) do
    project_root = get_project_root(project_id)
    
    config_paths = [
      # Project-specific settings (checked in to version control)
      Path.join(project_root, ".rubber_duck/settings.json"),
      # Project-specific local settings (gitignored)
      Path.join(project_root, ".rubber_duck/settings.local.json"),
      # Global user settings
      @global_config_path
    ]
    
    config_paths
    |> Enum.map(&expand_path/1)
    |> Enum.filter(&File.exists?/1)
    |> Enum.reduce(%{}, &merge_configs/2)
    |> validate_schema()
  end
  
  defp get_project_root(project_id) do
    # Fetch from the Project resource using Ash
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} -> project.root_path
      _ -> raise "Project #{project_id} not found"
    end
  end
  
  defp expand_path(path) do
    Path.expand(path)
  end
  
  defp merge_configs(config_path, acc) do
    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> deep_merge(acc, config)
          _ -> acc
        end
      _ -> acc
    end
  end
  
  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _k, _v1, v2 -> v2
    end)
  end
  
  defp validate_schema(config) do
    # Validates against Claude's exact JSON schema
    case config do
      %{"hooks" => hooks} when is_map(hooks) ->
        {:ok, validate_hook_structure(hooks)}
      _ ->
        {:error, "Invalid hooks configuration"}
    end
  end
  
  defp validate_hook_structure(hooks) do
    # Validate each hook type and structure
    hooks
  end
end
```

## 2. Matcher System Design

### Extensible Matcher Behavior

Using Elixir behaviors to create an extensible matcher system:

```elixir
defmodule RubberDuck.Hooks.Matcher do
  @callback match?(pattern :: String.t(), target :: String.t()) :: boolean()
  @callback priority() :: integer()
  
  @doc """
  Default implementation for exact string matching
  """
  def match?(pattern, target) when pattern == target, do: true
  def match?("*", _target), do: true
  def match?("", _target), do: true
  def match?(pattern, target) do
    # Check if it's a regex pattern (contains |)
    if String.contains?(pattern, "|") do
      RegexMatcher.match?(pattern, target)
    else
      false
    end
  end
end

defmodule RubberDuck.Hooks.Matchers.RegexMatcher do
  @behaviour RubberDuck.Hooks.Matcher
  
  def match?(pattern, target) do
    # Convert Claude's pipe-separated format to regex
    regex_pattern = pattern
    |> String.split("|")
    |> Enum.map(&Regex.escape/1)
    |> Enum.join("|")
    |> then(&"^(#{&1})$")
    
    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, target)
      _ -> false
    end
  end
  
  def priority(), do: 50
end
```

### Matcher Registry

A GenServer to manage and discover matchers dynamically:

```elixir
defmodule RubberDuck.Hooks.MatcherRegistry do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def register_matcher(name, module) do
    GenServer.call(__MODULE__, {:register, name, module})
  end
  
  def find_matching_hooks(event_type, tool_name, hooks_config) do
    GenServer.call(__MODULE__, {:find_matching, event_type, tool_name, hooks_config})
  end
  
  @impl true
  def handle_call({:find_matching, event_type, tool_name, hooks_config}, _from, state) do
    matching_hooks = case hooks_config[event_type] do
      nil -> []
      hook_specs -> 
        hook_specs
        |> Enum.filter(fn spec ->
          matcher = Map.get(spec, "matcher", "")
          # Only PreToolUse and PostToolUse use matchers
          if event_type in ["PreToolUse", "PostToolUse"] do
            RubberDuck.Hooks.Matcher.match?(matcher, tool_name)
          else
            true
          end
        end)
        |> Enum.flat_map(fn spec -> Map.get(spec, "hooks", []) end)
    end
    
    {:reply, matching_hooks, state}
  end
end
```

## 3. Event Bus Integration

### Project-Aware GenServer Event Bus

```elixir
defmodule RubberDuck.Hooks.EventBus do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def emit(project_id, event_name, data) do
    GenServer.cast(__MODULE__, {:emit, project_id, event_name, data})
  end
  
  def emit_sync(project_id, event_name, data) do
    GenServer.call(__MODULE__, {:emit_sync, project_id, event_name, data}, 30_000)
  end
  
  @impl true
  def handle_call({:emit_sync, project_id, event_name, data}, _from, state) do
    result = RubberDuck.Hooks.System.execute_hooks(project_id, event_name, data)
    {:reply, result, state}
  end
  
  @impl true
  def handle_cast({:emit, project_id, event_name, data}, state) do
    Task.start(fn ->
      RubberDuck.Hooks.System.execute_hooks(project_id, event_name, data)
    end)
    {:noreply, state}
  end
end
```

## 4. Hook Executor with Claude Compatibility

### Project-Aware Executor Implementation

The executor handles the actual hook execution while maintaining Claude's exact input/output format and sets the proper working directory:

```elixir
defmodule RubberDuck.Hooks.Executor do
  require Logger
  
  @timeout 60_000  # 60 second default timeout
  
  def execute_hooks(event_name, context) do
    # Get matching hooks
    hooks = RubberDuck.Hooks.MatcherRegistry.find_matching_hooks(
      event_name, 
      context.tool_name, 
      context.config
    )
    
    # Execute hooks in sequence (or parallel for independent hooks)
    Enum.reduce_while(hooks, {:ok, context}, fn hook, {:ok, acc_context} ->
      case execute_single_hook(hook, event_name, acc_context) do
        {:continue, new_context} -> {:cont, {:ok, new_context}}
        {:stop, reason} -> {:halt, {:stop, reason}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
  
  defp execute_single_hook(hook, event_name, context) do
    # Prepare input data matching Claude's format exactly
    input_data = build_hook_input(event_name, context)
    
    # Execute the command in the project directory
    timeout = Map.get(hook, "timeout", @timeout) * 1000
    command = Map.get(hook, "command", "")
    project_root = context.project_root
    
    case execute_command(command, input_data, timeout, project_root) do
      {:ok, exit_code, stdout, stderr} ->
        process_hook_result(event_name, exit_code, stdout, stderr)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp build_hook_input(event_name, context) do
    # Base fields for all events - use project root as cwd
    base = %{
      "session_id" => context.session_id,
      "transcript_path" => context.transcript_path,
      "cwd" => context.project_root || File.cwd!(),
      "hook_event_name" => event_name,
      "project_id" => context.project_id
    }
    
    # Add event-specific fields
    case event_name do
      "PreToolUse" ->
        Map.merge(base, %{
          "tool_name" => context.tool_name,
          "tool_input" => context.tool_input
        })
        
      "PostToolUse" ->
        Map.merge(base, %{
          "tool_name" => context.tool_name,
          "tool_input" => context.tool_input,
          "tool_response" => context.tool_response
        })
        
      "UserPromptSubmit" ->
        Map.merge(base, %{
          "prompt" => context.prompt,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        
      _ -> base
    end
  end
  
  defp execute_command(command, input_data, timeout, project_root) do
    json_input = Jason.encode!(input_data)
    
    # Resolve command path relative to project if it's a relative path
    resolved_command = resolve_command_path(command, project_root)
    
    task = Task.async(fn ->
      System.cmd("sh", ["-c", resolved_command], 
        input: json_input,
        stderr_to_stdout: false,
        cd: project_root,  # Execute in project directory
        env: [{"RUBBER_DUCK_PROJECT_ROOT", project_root}]
      )
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, exit_code, output, ""}
      {:ok, {output, stderr, exit_code}} ->
        {:ok, exit_code, output, stderr}
      nil ->
        {:error, :timeout}
    end
  end
  
  defp resolve_command_path(command, project_root) do
    # If the command references a file in .rubber_duck/, make it relative to project
    if String.starts_with?(command, ".rubber_duck/") or String.contains?(command, " .rubber_duck/") do
      String.replace(command, ".rubber_duck/", Path.join(project_root, ".rubber_duck/") <> "/")
    else
      command
    end
  end
  
  defp process_hook_result(event_name, exit_code, stdout, stderr) do
    case exit_code do
      0 ->
        # Try to parse JSON output
        case Jason.decode(stdout) do
          {:ok, json_output} ->
            handle_json_output(event_name, json_output)
          _ ->
            # Non-JSON output, continue normally
            {:continue, %{}}
        end
        
      2 ->
        # Blocking error - stderr is fed to system
        Logger.error("Hook blocked with error: #{stderr}")
        {:stop, stderr}
        
      _ ->
        # Non-blocking error
        Logger.warn("Hook failed with exit code #{exit_code}: #{stderr}")
        {:continue, %{}}
    end
  end
  
  defp handle_json_output(_event_name, %{"continue" => false, "stopReason" => reason}) do
    {:stop, reason}
  end
  
  defp handle_json_output("PreToolUse", json_output) do
    # Handle PreToolUse specific output
    case get_in(json_output, ["hookSpecificOutput", "permissionDecision"]) do
      "deny" -> 
        reason = get_in(json_output, ["hookSpecificOutput", "permissionDecisionReason"])
        {:stop, reason}
      _ ->
        {:continue, json_output}
    end
  end
  
  defp handle_json_output(_event_name, json_output) do
    {:continue, json_output}
  end
end
```

## 5. Integration with RubberDuck Tool System

### Project-Aware Tool System Adapter

Since the specific RubberDuck implementation wasn't found, here's a flexible adapter pattern that includes project context:

```elixir
defmodule RubberDuck.Hooks.ToolAdapter do
  @moduledoc """
  Adapter to integrate hooks with the existing RubberDuck tool system
  """
  
  defmacro __using__(opts) do
    quote do
      def before_tool_execution(project_id, tool_name, tool_input) do
        context = %{
          tool_name: tool_name,
          tool_input: tool_input,
          session_id: get_session_id(),
          transcript_path: get_transcript_path(project_id)
        }
        
        case RubberDuck.Hooks.EventBus.emit_sync(project_id, "PreToolUse", context) do
          {:ok, _} -> :continue
          {:stop, reason} -> {:stop, reason}
          {:error, error} -> {:error, error}
        end
      end
      
      def after_tool_execution(project_id, tool_name, tool_input, tool_response) do
        context = %{
          tool_name: tool_name,
          tool_input: tool_input,
          tool_response: tool_response,
          session_id: get_session_id(),
          transcript_path: get_transcript_path(project_id)
        }
        
        RubberDuck.Hooks.EventBus.emit(project_id, "PostToolUse", context)
      end
      
      defp get_transcript_path(project_id) do
        # Generate transcript path relative to project
        case RubberDuck.Workspace.get_project(project_id) do
          {:ok, project} ->
            Path.join([project.root_path, ".rubber_duck", "transcripts", 
                      "session_#{get_session_id()}.json"])
          _ ->
            nil
        end
      end
    end
  end
end
```

### Spark DSL Integration with Project Context

If RubberDuck uses Spark DSL for tool definitions, here's how to integrate with project awareness:

```elixir
defmodule RubberDuck.Tool.DSL do
  use Spark.Dsl
  
  defmacro tool(name, opts \\ [], do: block) do
    quote do
      # Original tool definition
      unquote(block)
      
      # Wrap with hooks
      defoverridable [execute: 2]
      
      def execute(project_id, input) do
        tool_name = unquote(name)
        
        # Pre-execution hook
        case RubberDuck.Hooks.ToolAdapter.before_tool_execution(project_id, tool_name, input) do
          :continue ->
            result = super(project_id, input)
            
            # Post-execution hook
            RubberDuck.Hooks.ToolAdapter.after_tool_execution(project_id, tool_name, input, result)
            
            result
            
          {:stop, reason} ->
            {:error, {:hook_blocked, reason}}
        end
      end
    end
  end
end
```

### Project Context Manager

A helper module to manage project-specific context:

```elixir
defmodule RubberDuck.Hooks.ProjectContext do
  @moduledoc """
  Manages project-specific hook context and lifecycle
  """
  
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def on_project_open(project_id) do
    GenServer.cast(__MODULE__, {:project_opened, project_id})
  end
  
  def on_project_close(project_id) do
    GenServer.cast(__MODULE__, {:project_closed, project_id})
  end
  
  def get_active_projects do
    GenServer.call(__MODULE__, :get_active_projects)
  end
  
  @impl true
  def init(_) do
    {:ok, %{active_projects: MapSet.new()}}
  end
  
  @impl true
  def handle_cast({:project_opened, project_id}, state) do
    # Load hooks for this project
    RubberDuck.Hooks.System.load_project_hooks(project_id)
    
    # Watch for configuration changes
    watch_project_config(project_id)
    
    new_active = MapSet.put(state.active_projects, project_id)
    {:noreply, %{state | active_projects: new_active}}
  end
  
  @impl true
  def handle_cast({:project_closed, project_id}, state) do
    # Unload hooks for this project
    RubberDuck.Hooks.System.unload_project_hooks(project_id)
    
    # Stop watching configuration
    unwatch_project_config(project_id)
    
    new_active = MapSet.delete(state.active_projects, project_id)
    {:noreply, %{state | active_projects: new_active}}
  end
  
  defp watch_project_config(project_id) do
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} ->
        config_path = Path.join(project.root_path, ".rubber_duck")
        # Use FileSystem library to watch for changes
        {:ok, _pid} = FileSystem.start_link(dirs: [config_path], name: :"watcher_#{project_id}")
        FileSystem.subscribe(:"watcher_#{project_id}")
      _ ->
        :ok
    end
  end
  
  defp unwatch_project_config(project_id) do
    # Stop the file watcher for this project
    case Process.whereis(:"watcher_#{project_id}") do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end
  
  @impl true
  def handle_info({:file_event, watcher_pid, {path, _events}}, state) do
    # Reload configuration if settings files changed
    if String.ends_with?(path, "settings.json") or String.ends_with?(path, "settings.local.json") do
      # Extract project_id from watcher name
      project_id = extract_project_id_from_watcher(watcher_pid)
      RubberDuck.Hooks.System.load_project_hooks(project_id)
    end
    {:noreply, state}
  end
  
  defp extract_project_id_from_watcher(watcher_pid) do
    # Implementation to map watcher PID back to project_id
    # This would typically use a registry or ETS table
  end
end
```

## 6. Performance Optimization with ETS Cache

```elixir
defmodule RubberDuck.Hooks.Cache do
  use GenServer
  
  @table_name :hook_cache
  @ttl :timer.minutes(5)
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def get_or_compute(key, compute_fn) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] when expiry > System.monotonic_time() ->
        {:ok, value}
      _ ->
        value = compute_fn.()
        put(key, value)
        {:ok, value}
    end
  end
  
  def put(key, value) do
    expiry = System.monotonic_time() + @ttl
    :ets.insert(@table_name, {key, value, expiry})
  end
  
  @impl true
  def init(_) do
    :ets.new(@table_name, [:named_table, :public, :set, 
             read_concurrency: true, write_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @ttl)
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time()
    :ets.select_delete(@table_name, [{{:"$1", :"$2", :"$3"}, 
                                      [{:<, :"$3", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end
end
```

## 7. Supervision Tree Structure

```elixir
defmodule RubberDuck.Hooks.Supervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # Core components
      {RubberDuck.Hooks.ConfigLoader, []},
      {RubberDuck.Hooks.MatcherRegistry, []},
      {RubberDuck.Hooks.EventBus, []},
      {RubberDuck.Hooks.Cache, []},
      
      # Dynamic supervisor for hook workers
      {DynamicSupervisor, name: RubberDuck.Hooks.WorkerSupervisor,
       strategy: :one_for_one, max_restarts: 10, max_seconds: 60},
      
      # Main hooks system
      {RubberDuck.Hooks.System, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## 8. Directory Structure

Following Claude's conventions adapted for RubberDuck with project-specific hooks:

```
# Project directory structure
my_project/
├── .rubber_duck/
│   ├── settings.json           # Project-specific hooks (version controlled)
│   ├── settings.local.json     # Local overrides (gitignored)
│   ├── hooks/                  # Project-specific hook scripts
│   │   ├── format_code.exs
│   │   ├── run_tests.sh
│   │   └── check_types.py
│   └── transcripts/            # Session transcripts
│       └── session_*.json

# Global user directory
~/.rubber_duck/
├── settings.json               # Global hooks for all projects
└── hooks/                      # Global hook scripts
    ├── security_check.sh
    └── license_check.py
```

### Gitignore recommendations

Add to your project's `.gitignore`:
```
.rubber_duck/settings.local.json
.rubber_duck/transcripts/
```

## 9. Example Hook Configurations

### Project-specific hooks in `my_project/.rubber_duck/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".rubber_duck/hooks/format_code.exs",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Compile",
        "hooks": [
          {
            "type": "command",
            "command": "mix test --cover"
          }
        ]
      }
    ]
  }
}
```

### Local overrides in `my_project/.rubber_duck/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": ".rubber_duck/hooks/custom_linter.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Global hooks in `~/.rubber_duck/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.rubber_duck/hooks/security_check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.rubber_duck/hooks/log_activity.py"
          }
        ]
      }
    ]
  }
}
```

### Example project hook script `.rubber_duck/hooks/format_code.exs`:

```elixir
#!/usr/bin/env elixir

# Read input from stdin
input = IO.read(:stdio, :all)
{:ok, data} = Jason.decode(input)

# Format based on file extension
case Path.extname(data["tool_input"]["path"] || "") do
  ".ex" -> System.cmd("mix", ["format", data["tool_input"]["path"]])
  ".exs" -> System.cmd("mix", ["format", data["tool_input"]["path"]])
  ".js" -> System.cmd("prettier", ["--write", data["tool_input"]["path"]])
  _ -> :ok
end

# Return success
IO.puts(Jason.encode!(%{continue: true}))
```

## 10. Security Considerations

Implementing Claude's security model in Elixir with project isolation:

```elixir
defmodule RubberDuck.Hooks.Security do
  @blocked_commands ~w(rm rf sudo chmod)
  @sensitive_paths ~w(.env .git secrets)
  
  def validate_hook_command(command, project_root) do
    cond do
      contains_blocked_command?(command) ->
        {:error, "Command contains blocked operations"}
      
      contains_sensitive_path?(command) ->
        {:error, "Command accesses sensitive paths"}
      
      escapes_project_root?(command, project_root) ->
        {:error, "Command attempts to access files outside project"}
        
      true ->
        :ok
    end
  end
  
  defp contains_blocked_command?(command) do
    Enum.any?(@blocked_commands, &String.contains?(command, &1))
  end
  
  defp contains_sensitive_path?(command) do
    Enum.any?(@sensitive_paths, &String.contains?(command, &1))
  end
  
  defp escapes_project_root?(command, project_root) do
    # Check for path traversal attempts
    String.contains?(command, "../") or 
    String.contains?(command, "..\\") or
    String.contains?(command, "~") and not String.starts_with?(command, "~/.rubber_duck/")
  end
  
  @doc """
  Validates that a hook script file is safe to execute
  """
  def validate_hook_file(file_path, project_root) do
    cond do
      # Must be within project or global hooks directory
      not within_allowed_directory?(file_path, project_root) ->
        {:error, "Hook file must be in .rubber_duck/hooks directory"}
      
      # Check file permissions (should not be world-writable)
      world_writable?(file_path) ->
        {:error, "Hook file has unsafe permissions"}
        
      true ->
        :ok
    end
  end
  
  defp within_allowed_directory?(file_path, project_root) do
    normalized = Path.expand(file_path)
    
    # Allow project hooks
    String.starts_with?(normalized, Path.join(project_root, ".rubber_duck/hooks/")) or
    # Allow global hooks
    String.starts_with?(normalized, Path.expand("~/.rubber_duck/hooks/"))
  end
  
  defp world_writable?(file_path) do
    case File.stat(file_path) do
      {:ok, %{mode: mode}} ->
        # Check if world-writable bit is set
        (mode &&& 0o002) != 0
      _ ->
        true  # Assume unsafe if we can't check
    end
  end
end
```

### Project Isolation

The hooks system enforces project boundaries:

1. **Working Directory**: Hooks always execute with the project root as the working directory
2. **Path Resolution**: Relative paths in hooks are resolved relative to the project root
3. **Environment Variables**: `RUBBER_DUCK_PROJECT_ROOT` is set for hook scripts
4. **File Access**: Security checks prevent accessing files outside the project (except for global hooks)

### Hook Script Security

Best practices for hook scripts:

```bash
#!/bin/bash
# Example secure hook script

# Use project root from environment
PROJECT_ROOT="${RUBBER_DUCK_PROJECT_ROOT:-$(pwd)}"

# Validate we're in a project directory
if [ ! -f "$PROJECT_ROOT/.rubber_duck/settings.json" ]; then
    echo "Not in a valid RubberDuck project" >&2
    exit 1
fi

# Only operate on files within the project
find "$PROJECT_ROOT" -name "*.ex" -type f | while read -r file; do
    # Process only if file is within project bounds
    realpath "$file" | grep -q "^$PROJECT_ROOT/" && mix format "$file"
done
```

## Implementation Recommendations

### Hook Loading Order and Precedence

The hooks system loads configurations in the following order (later ones override earlier ones):

1. **Global hooks** (`~/.rubber_duck/settings.json`) - Applied to all projects
2. **Project hooks** (`<project>/.rubber_duck/settings.json`) - Project-specific, version controlled
3. **Local hooks** (`<project>/.rubber_duck/settings.local.json`) - Personal overrides, gitignored

This allows for:
- Organization-wide standards in project hooks
- Personal productivity tools in global hooks  
- Temporary debugging hooks in local settings

### Phase 1: Core Infrastructure
1. Implement the basic GenServer architecture with project awareness
2. Create the configuration loader with JSON parsing and merging
3. Set up the matcher system with exact string matching
4. Build the event bus for hook execution

### Phase 2: Claude Compatibility
1. Implement all hook event types
2. Ensure exact JSON input/output format matching
3. Handle all exit codes and control flow patterns
4. Add security validations

### Phase 3: Tool System Integration
1. Create adapters for existing RubberDuck tools
2. Implement Spark DSL macros if applicable
3. Add performance monitoring and caching
4. Set up the supervision tree

### Phase 4: Advanced Features
1. Add more sophisticated matchers (glob patterns, MCP tool names)
2. Implement parallel hook execution where safe
3. Add hook composition and dependencies
4. Create development tools and debugging aids

### Phase 5: Project Management
1. Implement automatic hook loading on project open
2. Add file watching for configuration changes
3. Create project context lifecycle management
4. Build multi-project support

This design provides a robust, extensible hooks system that maintains exact compatibility with Claude's JSON format while leveraging Elixir's strengths in concurrency, fault tolerance, and pattern matching. The modular architecture allows for gradual implementation and easy integration with any existing RubberDuck tool system.
