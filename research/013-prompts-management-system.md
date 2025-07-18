# Prompt Management System Design for RubberDuck AI

## System architecture leverages Elixir best practices

The research reveals critical design decisions for building a secure, scalable prompt management system in Elixir. The architecture combines Solid templates for safety, Ash Framework for multi-tenant data management, and industry-standard patterns from leading AI coding assistants.

## Core technology choices

### Template engine: Solid over EEx
Standard EEx templates pose significant security risks for user-generated content, including arbitrary code execution and atom exhaustion attacks. Solid, a Liquid template implementation for Elixir, provides:
- Sandboxed execution environment preventing code injection
- Compile-time validation with `~LIQUID` sigil
- Built-in security features with configurable restrictions
- Type-safe variable handling without atom generation

### Multi-tenant architecture with Ash
The system implements context-based multitenancy using Ash Framework's declarative patterns:

```elixir
defmodule RubberDuck.Prompts.Prompt do
  use Ash.Resource,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource, AshGraphql.Resource]

  multitenancy do
    strategy :context
  end

  postgres do
    table "prompts"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :description, :string
    attribute :content, :string, allow_nil?: false
    attribute :template_variables, :map, default: %{}
    attribute :scope, :atom, constraints: [one_of: [:global, :project, :user]]
    attribute :visibility, :atom, constraints: [one_of: [:public, :private, :shared]]
    attribute :status, :atom, constraints: [one_of: [:draft, :published, :archived]]
    attribute :metadata, :map, default: %{
      "usage_count" => 0,
      "last_used_at" => nil,
      "ai_model_preferences" => %{}
    }
    timestamps()
  end

  relationships do
    belongs_to :organization, RubberDuck.Accounts.Organization
    belongs_to :user, RubberDuck.Accounts.User
    belongs_to :project, RubberDuck.Projects.Project
    has_many :versions, RubberDuck.Prompts.PromptVersion
    many_to_many :categories, RubberDuck.Prompts.Category
    many_to_many :tags, RubberDuck.Prompts.Tag
  end
end
```

## Template storage and organization

### File-based organization inspired by industry leaders
Following patterns from GitHub Copilot and Cursor, prompts are organized hierarchically:

```
.rubberduck/
├── prompts/
│   ├── global/           # Server-wide prompts
│   ├── project/          # Project-specific prompts
│   └── user/             # Personal prompts
└── prompt-rules.md       # Project-level instructions
```

### Database schema for rich metadata
```elixir
defmodule RubberDuck.Prompts.PromptVersion do
  use Ash.Resource,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :version_number, :integer, allow_nil?: false
    attribute :content, :string, allow_nil?: false
    attribute :variables_schema, :map  # JSON Schema for variables
    attribute :change_description, :string
    timestamps()
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Prompt
    belongs_to :created_by, RubberDuck.Accounts.User
  end
end
```

## Template processing pipeline

### Safe template compilation with caching
```elixir
defmodule RubberDuck.Templates.Compiler do
  use GenServer
  
  @ets_table :compiled_templates
  
  def compile_and_cache(template_id, content) do
    case Solid.parse(content) do
      {:ok, parsed} ->
        compiled = optimize_template(parsed)
        :ets.insert(@ets_table, {template_id, compiled, System.system_time(:second)})
        {:ok, compiled}
      {:error, errors} ->
        {:error, format_errors(errors)}
    end
  end
  
  def render(template_id, variables) do
    with {:ok, compiled} <- get_cached_or_compile(template_id),
         {:ok, validated_vars} <- validate_variables(variables),
         {:ok, result} <- Solid.render(compiled, validated_vars) do
      track_usage(template_id)
      {:ok, result}
    end
  end
end
```

### Variable validation and type safety
```elixir
defmodule RubberDuck.Templates.VariableValidator do
  def validate_against_schema(variables, schema) do
    case ExJsonSchema.Validator.validate(schema, variables) do
      :ok -> {:ok, variables}
      {:error, errors} -> {:error, format_validation_errors(errors)}
    end
  end
  
  def extract_variables_from_template(content) do
    ~r/\{\{\s*(\w+(?:\.\w+)*)\s*\}\}/
    |> Regex.scan(content)
    |> Enum.map(fn [_, var] -> String.split(var, ".") end)
    |> Enum.uniq()
  end
end
```

## Integration with conversation system

### Context-aware prompt selection
```elixir
defmodule RubberDuck.Prompts.Selector do
  def find_relevant_prompts(conversation_context) do
    %{
      file_types: file_types,
      project_id: project_id,
      recent_messages: messages
    } = conversation_context
    
    RubberDuck.Prompts.Prompt
    |> filter_by_scope(project_id)
    |> filter_by_context(file_types)
    |> rank_by_relevance(messages)
    |> Ash.read!()
  end
  
  defp filter_by_scope(query, project_id) do
    Ash.Query.filter(query, 
      scope in [:global, :project] and 
      (is_nil(project_id) or project_id == ^project_id)
    )
  end
end
```

### Dynamic variable injection from conversation
```elixir
defmodule RubberDuck.Prompts.VariableInjector do
  def inject_from_conversation(prompt_content, conversation) do
    variables = %{
      "current_file" => conversation.active_file,
      "file_content" => conversation.file_content,
      "language" => detect_language(conversation.active_file),
      "selected_text" => conversation.selection,
      "conversation_history" => format_history(conversation.messages)
    }
    
    RubberDuck.Templates.Compiler.render(prompt_content, variables)
  end
end
```

## Security implementation

### Rate limiting per user/project
```elixir
defmodule RubberDuck.RateLimiter do
  use GenServer
  
  def check_rate_limit(user_id, action, limit \\ 100) do
    key = {user_id, action, current_window()}
    
    case :ets.update_counter(:rate_limits, key, 1, {key, 0}) do
      count when count <= limit -> :ok
      _ -> {:error, :rate_limit_exceeded}
    end
  end
  
  defp current_window do
    div(System.system_time(:second), 60)  # 1-minute windows
  end
end
```

### Template sandboxing and resource limits
```elixir
defmodule RubberDuck.Templates.Sandbox do
  @max_template_size 50_000
  @max_render_time 5_000
  @max_variables 100
  
  def validate_template(content) do
    with :ok <- check_size(content),
         :ok <- check_complexity(content),
         :ok <- check_variable_count(content) do
      {:ok, content}
    end
  end
  
  def render_with_timeout(template, variables) do
    task = Task.async(fn ->
      Solid.render(template, variables)
    end)
    
    case Task.await(task, @max_render_time) do
      {:ok, result} -> {:ok, result}
      _ -> {:error, :render_timeout}
    end
  end
end
```

## Performance optimization

### ETS-based caching with TTL
```elixir
defmodule RubberDuck.Templates.Cache do
  use GenServer
  
  def init(_) do
    table = :ets.new(:template_cache, [
      :set, :public, :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    schedule_cleanup()
    {:ok, %{table: table}}
  end
  
  def get_or_compile(template_id, compile_fn) do
    case :ets.lookup(:template_cache, template_id) do
      [{^template_id, compiled, timestamp}] ->
        if fresh?(timestamp), do: {:ok, compiled}, else: refresh(template_id, compile_fn)
      [] ->
        refresh(template_id, compile_fn)
    end
  end
  
  defp fresh?(timestamp) do
    System.system_time(:second) - timestamp < 3600  # 1 hour TTL
  end
end
```

### Database query optimization
```elixir
defmodule RubberDuck.Prompts.Queries do
  import Ecto.Query
  
  def search_prompts(query_string, filters) do
    base_query = 
      from p in Prompt,
        where: fragment("? @@ websearch_to_tsquery('english', ?)", 
                       p.search_vector, ^query_string)
    
    base_query
    |> apply_filters(filters)
    |> preload([:categories, :tags])
    |> limit(20)
  end
  
  def create_search_index do
    execute """
    CREATE INDEX prompts_search_idx ON prompts 
    USING GIN (to_tsvector('english', title || ' ' || description || ' ' || content))
    """
  end
end
```

## API design for Phase 6 integration

### GraphQL API for rich queries
```elixir
defmodule RubberDuck.Prompts do
  use Ash.Domain, extensions: [AshGraphql.Domain]
  
  graphql do
    queries do
      list :search_prompts, :search do
        argument :query, :string
        argument :scope, :prompt_scope
        argument :categories, {:array, :id}
      end
      
      get :prompt_with_variables, :read do
        type :prompt_with_schema
      end
    end
    
    mutations do
      create :create_prompt, :create
      update :update_prompt, :update
      create :create_from_template, :duplicate
    end
  end
end
```

### REST endpoints for simple operations
```elixir
defmodule RubberDuckWeb.PromptController do
  use RubberDuckWeb, :controller
  
  def render_prompt(conn, %{"id" => id, "variables" => variables}) do
    with {:ok, prompt} <- Prompts.get_prompt(id, actor: conn.assigns.current_user),
         {:ok, rendered} <- Templates.render(prompt.content, variables) do
      json(conn, %{
        prompt_id: id,
        rendered_content: rendered,
        variables_used: Map.keys(variables)
      })
    end
  end
  
  def list_by_context(conn, %{"file_type" => file_type}) do
    prompts = Prompts.find_by_file_type(file_type, actor: conn.assigns.current_user)
    json(conn, %{prompts: prompts})
  end
end
```

## Monitoring and telemetry

### Comprehensive metrics collection
```elixir
defmodule RubberDuck.Prompts.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  
  def metrics do
    [
      counter("prompts.render.count", tags: [:scope, :status]),
      summary("prompts.render.duration", unit: {:native, :millisecond}),
      distribution("prompts.template.size", buckets: [1_000, 5_000, 10_000, 50_000]),
      last_value("prompts.cache.hit_rate"),
      counter("prompts.errors.count", tags: [:error_type])
    ]
  end
  
  def handle_event([:prompt, :render, :stop], measurements, metadata, _) do
    if measurements.duration > 1_000_000 do  # 1 second
      Logger.warn("Slow prompt render", 
        prompt_id: metadata.prompt_id,
        duration_ms: measurements.duration / 1_000
      )
    end
  end
end
```

## Migration path and deployment

### Gradual rollout strategy
1. Deploy core infrastructure with basic CRUD operations
2. Implement template compilation and caching layer
3. Add advanced features (versioning, categories, tags)
4. Integrate with conversation system from Phase 6
5. Enable collaborative features and sharing

### Database migrations
```elixir
defmodule RubberDuck.Repo.Migrations.CreatePromptSystem do
  use Ecto.Migration
  
  def change do
    # Create prompts table with all required fields
    create table(:prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :content, :text, null: false
      add :template_variables, :map, default: %{}
      add :scope, :string, null: false
      add :organization_id, references(:organizations, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)
      add :project_id, references(:projects, type: :binary_id)
      
      timestamps()
    end
    
    # Create indexes for performance
    create index(:prompts, [:user_id, :scope])
    create index(:prompts, [:project_id, :scope])
    create index(:prompts, [:updated_at])
    
    # Full-text search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    execute """
    CREATE INDEX prompts_search_idx ON prompts 
    USING GIN ((title || ' ' || content) gin_trgm_ops)
    """
  end
end
```

This design provides a robust, secure, and performant prompt management system that integrates seamlessly with RubberDuck's existing architecture while incorporating best practices from leading AI coding assistants.
