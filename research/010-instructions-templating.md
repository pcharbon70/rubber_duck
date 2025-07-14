# Building a composable markdown instruction system for RubberDuck

The modern AI coding assistant landscape has converged on markdown-based instruction systems as the de facto standard for project-specific context. Claude.md, Cursor's rule system, and GitHub Copilot's instruction files all demonstrate that developers need flexible, version-controlled ways to guide AI behavior. For RubberDuck, implementing such a system in Elixir presents unique opportunities to leverage the BEAM's strengths while learning from established patterns.

## Learning from existing instruction systems

**Claude Code and Cursor have pioneered distinct approaches that inform our design**. Claude automatically ingests `claude.md` files from project roots, prioritizing simplicity with a single file containing project context. The system supports dynamic instruction addition through the `#` key and maintains brevity requirements (under 500 lines) due to token constraints. Cursor evolved from a single `.cursorrules` file to a sophisticated multi-file system using `.cursor/rules/*.mdc` files with metadata-driven rule types: Always, Auto Attached, Agent Requested, and Manual.

The emerging pattern across tools shows hierarchical file discovery with predictable naming conventions. Files in project roots take precedence over workspace-level instructions, which override global settings. Most systems support variable interpolation using `${variable}` syntax and implement conditional logic through metadata or specialized syntax blocks. Frontmatter has become the standard for storing rule metadata, controlling scope, priority, and applicability.

## Elixir template engine selection

**For RubberDuck, the choice between EEx and Solid represents a fundamental security decision**. EEx offers native Phoenix integration and full Elixir power within templates but creates atoms for variables, potentially exhausting memory with user-provided content. Its `<%= %>` syntax is familiar to Phoenix developers, and it supports complex logic, but direct runtime access poses unacceptable security risks for user templates.

Solid emerges as the recommended solution for user-provided markdown templates. This strict Liquid implementation provides `{{ variable }}` syntax for output and `{% if %}` blocks for logic while preventing code execution. Its design specifically targets user content safety:

```elixir
defmodule RubberDuck.InstructionProcessor do
  def process_user_template(template_content, context) do
    with {:ok, parsed} <- Solid.parse(template_content),
         {:ok, rendered} <- Solid.render(parsed, context) do
      # Convert rendered template to HTML via markdown
      html = rendered |> to_string() |> Earmark.as_html!()
      {:ok, html}
    else
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end
end
```

For markdown processing, **Earmark provides the best balance of features and safety**. Its pure Elixir implementation supports EEx preprocessing with the `eex: true` option, though this should only be used with trusted system templates. MDEx offers superior performance through its Rust-based implementation but requires additional complexity for template integration.

## Caching architecture for dynamic content

**ETS-based caching with Cachex provides the foundation for high-performance instruction serving**. The caching strategy must balance memory usage with access speed while supporting real-time updates. Cachex's advanced features like TTL expiration, cache warming, and distributed synchronization align perfectly with RubberDuck's requirements:

```elixir
defmodule RubberDuck.InstructionCache do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize Cachex with appropriate limits
    {:ok, _} = Cachex.start_link(:instruction_cache, [
      limit: 1000,
      default_ttl: :timer.hours(1),
      fallback: &fetch_instruction/1,
      warmers: [
        warmer(module: InstructionWarmer, state: %{})
      ]
    ])
    
    {:ok, %{}}
  end
  
  def get_instruction(instruction_id, context) do
    cache_key = build_cache_key(instruction_id, context)
    
    case Cachex.fetch(:instruction_cache, cache_key) do
      {:ok, nil} -> 
        # Cache miss - compile and cache
        result = compile_instruction(instruction_id, context)
        Cachex.put(:instruction_cache, cache_key, result)
        result
      {:ok, cached} -> 
        cached
      {:error, _} = error -> 
        error
    end
  end
  
  defp build_cache_key(id, context) do
    context_hash = :crypto.hash(:sha256, :erlang.term_to_binary(context))
    "instruction:#{id}:#{Base.encode16(context_hash)}"
  end
end
```

**Version-based cache invalidation prevents stale content while minimizing recompilation**. When instruction files change, increment a global version number and use it in cache keys. This approach allows gradual migration to new content without forcing immediate recompilation of all cached instructions.

## File watching and real-time updates

**FileSystem provides cross-platform file monitoring with minimal overhead**. The implementation must handle platform differences gracefully - FSEvents on macOS, inotify on Linux, and ReadDirectoryChangesW on Windows. Debouncing prevents excessive recompilation during rapid file edits:

```elixir
defmodule RubberDuck.InstructionWatcher do
  use GenServer
  
  @debounce_ms 100
  
  def init(instruction_dirs) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: instruction_dirs)
    FileSystem.subscribe(watcher_pid)
    
    {:ok, %{
      watcher_pid: watcher_pid,
      pending_changes: %{},
      processor: InstructionProcessor
    }}
  end
  
  def handle_info({:file_event, _pid, {path, events}}, state) do
    if markdown_file?(path) and meaningful_event?(events) do
      # Cancel existing timer for this path
      state = cancel_pending_timer(path, state)
      
      # Schedule debounced processing
      timer_ref = Process.send_after(self(), {:process_file, path}, @debounce_ms)
      new_pending = Map.put(state.pending_changes, path, timer_ref)
      
      {:noreply, %{state | pending_changes: new_pending}}
    else
      {:noreply, state}
    end
  end
  
  def handle_info({:process_file, path}, state) do
    # Clear pending timer
    {_, new_pending} = Map.pop(state.pending_changes, path)
    
    # Invalidate cache and notify clients
    InstructionCache.invalidate_path(path)
    broadcast_update(path)
    
    {:noreply, %{state | pending_changes: new_pending}}
  end
end
```

## GenServer integration patterns

**The supervision tree architecture ensures fault tolerance while maintaining clear separation of concerns**. Each component handles a specific aspect of the instruction system:

```elixir
defmodule RubberDuck.InstructionSupervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = [
      # Core services
      {RubberDuck.InstructionCache, []},
      {RubberDuck.InstructionWatcher, instruction_directories()},
      {RubberDuck.TemplateProcessor, []},
      {RubberDuck.SecuritySandbox, []},
      
      # Integration services  
      {RubberDuck.LLMContextBuilder, []},
      {RubberDuck.InstructionSelector, []},
      
      # Supporting services
      {RubberDuck.RateLimiter, []},
      {RubberDuck.MetricsCollector, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Message passing between services follows clear patterns**. The InstructionWatcher notifies the Cache about file changes, which broadcasts updates through Phoenix PubSub to connected clients. The TemplateProcessor requests sandboxed evaluation from SecuritySandbox, ensuring user templates never execute dangerous code.

## Security-first template processing

**Multi-layered security prevents template injection attacks**. The first layer validates template syntax and structure, rejecting malformed input. The second layer sanitizes variable names and values, preventing path traversal or code injection. The third layer executes templates in a restricted environment using Solid's built-in safety:

```elixir
defmodule RubberDuck.TemplateSecurityPipeline do
  def process_user_template(template, variables, user) do
    with :ok <- validate_template_size(template),
         :ok <- check_rate_limit(user),
         {:ok, safe_vars} <- sanitize_variables(variables),
         {:ok, parsed} <- Solid.parse(template),
         {:ok, rendered} <- Solid.render(parsed, safe_vars) do
      {:ok, rendered}
    else
      {:error, reason} -> handle_security_error(reason, user)
    end
  end
  
  defp sanitize_variables(variables) do
    sanitized = variables
    |> Enum.map(fn {k, v} -> 
      {sanitize_key(k), sanitize_value(v)}
    end)
    |> Enum.into(%{})
    
    {:ok, sanitized}
  end
  
  defp sanitize_key(key) when is_binary(key) do
    key
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
    |> String.slice(0, 50)
  end
  
  defp sanitize_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[<>&"']/, "")
    |> String.slice(0, 1000)
  end
  defp sanitize_value(value), do: value
end
```

## Client integration patterns

**The instruction system exposes a clean API for CLI, TUI, and Web clients**. Each client loads instruction files from the local filesystem and sends them to the server. The server validates, processes, and caches the compiled instructions:

```elixir
defmodule RubberDuckWeb.InstructionController do
  use RubberDuckWeb, :controller
  
  def upload_instructions(conn, %{"project_id" => project_id, "files" => files}) do
    user = conn.assigns.current_user
    
    with :ok <- validate_file_count(files),
         {:ok, instructions} <- process_instruction_files(files, user),
         :ok <- InstructionManager.store_instructions(project_id, instructions) do
      json(conn, %{status: "success", instruction_count: length(instructions)})
    else
      {:error, reason} -> 
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
  
  def get_compiled_instructions(conn, %{"project_id" => project_id, "context" => context}) do
    user = conn.assigns.current_user
    
    case InstructionManager.get_compiled(project_id, context, user) do
      {:ok, compiled} -> json(conn, %{instructions: compiled})
      {:error, reason} -> 
        conn
        |> put_status(:not_found)
        |> json(%{error: reason})
    end
  end
end
```

**Phoenix Channels enable real-time instruction updates**. When instruction files change on disk, connected clients receive notifications to refresh their cached content:

```elixir
defmodule RubberDuckWeb.InstructionChannel do
  use RubberDuckWeb, :channel
  
  def join("instructions:" <> project_id, _params, socket) do
    if authorized?(socket, project_id) do
      {:ok, assign(socket, :project_id, project_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
  
  def handle_info({:instruction_updated, instruction_id}, socket) do
    push(socket, "instruction_update", %{
      id: instruction_id,
      timestamp: DateTime.utc_now()
    })
    {:noreply, socket}
  end
end
```

## Implementation recommendations

**Start with a phased rollout to manage complexity**. Phase 1 implements basic markdown loading and caching with Solid templates. Phase 2 adds file watching and real-time updates. Phase 3 integrates with the LLM service architecture, implementing context window optimization and dynamic instruction selection.

**Monitor performance metrics from day one**. Track template compilation time, cache hit rates, memory usage, and security violations. Use Telemetry for consistent metric collection:

```elixir
:telemetry.attach(
  "instruction-metrics",
  [:rubberduck, :instruction, :cache_hit],
  &handle_metric/4,
  nil
)
```

**Design for extensibility** by keeping the core instruction format simple while supporting metadata-driven extensions. Follow the precedent set by Cursor and GitHub Copilot - start with basic variable interpolation and conditionals, then add advanced features based on user needs.

The RubberDuck instruction system can provide a powerful, secure foundation for AI-assisted coding by combining Elixir's strengths with lessons learned from existing tools. By prioritizing security, performance, and developer experience, this implementation will serve as a differentiating feature while maintaining the safety and reliability users expect.
