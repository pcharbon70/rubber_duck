# Unified Command Abstraction Layer for RubberDuck

## Overview

The Unified Command Abstraction Layer provides a single point of command processing that works seamlessly across all client interfaces (CLI, LiveView, TUI, WebSocket). This design eliminates code duplication and ensures consistent behavior regardless of the client type.

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Client Layer                                 │
├─────────────────┬─────────────────┬─────────────────┬───────────┤
│   CLI Client    │ LiveView Client │  TUI Client     │ WebSocket │
├─────────────────┼─────────────────┼─────────────────┼───────────┤
│   CLI Adapter   │ LiveView Adapter│  TUI Adapter    │ WS Adapter│
└─────────────────┴─────────────────┴─────────────────┴───────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                Command Abstraction Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  • Command Parser (Optimus)                                     │
│  • Command Validator                                            │
│  • Command Authorizer                                           │
│  • Response Formatter                                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Execution Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  • Engine System (Phases 2-3)                                  │
│  • Workflow Orchestration (Phase 4)                            │
│  • LLM Services                                                │
│  • Memory Management                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

## 1. Command Structure Definition

```elixir
defmodule RubberDuck.Commands.Command do
  @moduledoc """
  Unified command structure used across all client interfaces.
  """
  
  @type t :: %__MODULE__{
    name: atom(),
    subcommand: atom() | nil,
    args: map(),
    options: map(),
    context: RubberDuck.Commands.Context.t(),
    client_type: :cli | :liveview | :tui | :websocket,
    format: :json | :text | :table | :markdown
  }
  
  defstruct [
    :name,
    :subcommand,
    :args,
    :options,
    :context,
    :client_type,
    :format
  ]
end

defmodule RubberDuck.Commands.Context do
  @type t :: %__MODULE__{
    user_id: String.t(),
    project_id: String.t() | nil,
    conversation_id: String.t() | nil,
    session_id: String.t(),
    permissions: list(atom()),
    metadata: map()
  }
  
  defstruct [
    :user_id,
    :project_id,
    :conversation_id,
    :session_id,
    :permissions,
    :metadata
  ]
end
```

## 2. Command Parser Using Optimus

```elixir
defmodule RubberDuck.Commands.Parser do
  @moduledoc """
  Unified command parser that converts client-specific input into 
  standardized Command structs.
  """
  
  def parse(input, client_type, context) do
    case client_type do
      :cli -> parse_cli_input(input, context)
      :websocket -> parse_websocket_message(input, context)
      :liveview -> parse_liveview_params(input, context)
      :tui -> parse_tui_input(input, context)
    end
  end
  
  defp parse_cli_input(args, context) do
    optimus_spec()
    |> Optimus.parse(args)
    |> case do
      {[:analyze | subcommands], options} ->
        build_command(:analyze, subcommands, options, :cli, context)
        
      {[:generate | subcommands], options} ->
        build_command(:generate, subcommands, options, :cli, context)
        
      {[:complete | subcommands], options} ->
        build_command(:complete, subcommands, options, :cli, context)
        
      {_unknown, _options} ->
        {:error, "Unknown command"}
    end
  end
  
  defp optimus_spec do
    Optimus.new!(
      name: "rubber_duck",
      description: "AI-powered coding assistant",
      version: "1.0.0",
      author: "RubberDuck Team",
      about: "Intelligent code analysis and generation",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        analyze: [
          name: "analyze",
          about: "Analyze code files or projects",
          args: [
            file_path: [
              value_name: "FILE_PATH",
              help: "Path to file or directory to analyze",
              required: false
            ]
          ],
          flags: [
            recursive: [
              short: "-r",
              long: "--recursive",
              help: "Analyze directories recursively"
            ],
            include_security: [
              long: "--security",
              help: "Include security analysis"
            ]
          ],
          options: [
            format: [
              value_name: "FORMAT",
              short: "-f",
              long: "--format",
              help: "Output format (json, text, table)",
              default: "text"
            ],
            language: [
              value_name: "LANGUAGE",
              short: "-l",
              long: "--language",
              help: "Force specific language detection"
            ]
          ]
        ],
        generate: [
          name: "generate",
          about: "Generate code from descriptions",
          args: [
            description: [
              value_name: "DESCRIPTION",
              help: "Natural language description of what to generate",
              required: true
            ]
          ],
          options: [
            language: [
              value_name: "LANGUAGE",
              short: "-l",
              long: "--language",
              help: "Target programming language",
              default: "elixir"
            ],
            output_file: [
              value_name: "OUTPUT_FILE",
              short: "-o",
              long: "--output",
              help: "Output file path"
            ]
          ]
        ],
        complete: [
          name: "complete",
          about: "Get code completions",
          args: [
            file_path: [
              value_name: "FILE_PATH",
              help: "File to complete",
              required: true
            ]
          ],
          options: [
            position: [
              value_name: "POSITION",
              short: "-p",
              long: "--position",
              help: "Cursor position (line:column)",
              required: true
            ],
            max_suggestions: [
              value_name: "MAX",
              short: "-n",
              long: "--max",
              help: "Maximum number of suggestions",
              default: "5"
            ]
          ]
        ]
      ]
    )
  end
  
  defp build_command(name, subcommands, options, client_type, context) do
    %RubberDuck.Commands.Command{
      name: name,
      subcommand: List.first(subcommands),
      args: extract_args(options),
      options: extract_options(options),
      context: context,
      client_type: client_type,
      format: determine_format(options, client_type)
    }
  end
end
```

## 3. Unified Command Processor

```elixir
defmodule RubberDuck.Commands.Processor do
  @moduledoc """
  Central command processing engine that executes commands 
  and formats responses for different client types.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def execute(command_struct) do
    GenServer.call(__MODULE__, {:execute, command_struct}, 30_000)
  end
  
  def init(_opts) do
    {:ok, %{
      handlers: load_command_handlers(),
      validators: load_validators(),
      formatters: load_formatters()
    }}
  end
  
  def handle_call({:execute, command}, _from, state) do
    result = command
    |> validate_command(state.validators)
    |> authorize_command()
    |> execute_with_handler(state.handlers)
    |> format_response(command.format, command.client_type, state.formatters)
    
    {:reply, result, state}
  end
  
  defp validate_command(command, validators) do
    case Map.get(validators, command.name) do
      nil -> {:error, "Unknown command: #{command.name}"}
      validator -> validator.validate(command)
    end
  end
  
  defp authorize_command({:ok, command}) do
    case RubberDuck.Authorization.can_execute?(command) do
      true -> {:ok, command}
      false -> {:error, "Unauthorized"}
    end
  end
  defp authorize_command(error), do: error
  
  defp execute_with_handler({:ok, command}, handlers) do
    handler = Map.get(handlers, command.name)
    
    case handler do
      nil -> {:error, "No handler for command: #{command.name}"}
      handler_module -> handler_module.execute(command)
    end
  end
  defp execute_with_handler(error, _), do: error
  
  defp format_response({:ok, result}, format, client_type, formatters) do
    formatter = get_formatter(format, client_type, formatters)
    {:ok, formatter.format(result)}
  end
  defp format_response(error, _, _, _), do: error
end
```

## 4. Command Handlers

```elixir
defmodule RubberDuck.Commands.Handlers.Analyze do
  @behaviour RubberDuck.Commands.Handler
  
  @impl true
  def execute(%{name: :analyze, args: args, options: options, context: context}) do
    file_path = Map.get(args, :file_path, ".")
    recursive = Map.get(options, :recursive, false)
    include_security = Map.get(options, :include_security, false)
    
    analysis_options = %{
      recursive: recursive,
      include_security: include_security,
      project_id: context.project_id
    }
    
    case RubberDuck.Analysis.analyze_path(file_path, analysis_options) do
      {:ok, results} -> {:ok, %{analysis_results: results, file_path: file_path}}
      {:error, reason} -> {:error, "Analysis failed: #{reason}"}
    end
  end
end

defmodule RubberDuck.Commands.Handlers.Generate do
  @behaviour RubberDuck.Commands.Handler
  
  @impl true
  def execute(%{name: :generate, args: args, options: options, context: context}) do
    description = Map.get(args, :description)
    language = Map.get(options, :language, "elixir")
    output_file = Map.get(options, :output_file)
    
    generation_request = %{
      description: description,
      language: language,
      context: build_generation_context(context),
      stream: false
    }
    
    case RubberDuck.Generation.generate_code(generation_request) do
      {:ok, generated_code} ->
        result = %{
          generated_code: generated_code,
          language: language,
          description: description
        }
        
        # Optionally save to file
        if output_file do
          File.write(output_file, generated_code)
          result = Map.put(result, :saved_to, output_file)
        end
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, "Generation failed: #{reason}"}
    end
  end
  
  defp build_generation_context(context) do
    %{
      project_id: context.project_id,
      user_preferences: get_user_preferences(context.user_id),
      memory_context: get_relevant_memory(context)
    }
  end
end
```

## 5. Response Formatters

```elixir
defmodule RubberDuck.Commands.Formatters do
  @moduledoc """
  Format command results for different client types and output formats.
  """
  
  def format(result, :json, _client_type) do
    Jason.encode!(result)
  end
  
  def format(result, :text, :cli) do
    case result do
      %{analysis_results: results} -> format_analysis_text(results)
      %{generated_code: code} -> format_generation_text(code)
      %{completions: completions} -> format_completions_text(completions)
    end
  end
  
  def format(result, :table, :cli) do
    case result do
      %{analysis_results: results} -> format_analysis_table(results)
      %{completions: completions} -> format_completions_table(completions)
      _ -> format(result, :text, :cli)
    end
  end
  
  def format(result, :markdown, :liveview) do
    case result do
      %{analysis_results: results} -> format_analysis_markdown(results)
      %{generated_code: code} -> format_generation_markdown(code)
      _ -> format_generic_markdown(result)
    end
  end
  
  defp format_analysis_text(results) do
    """
    Analysis Results:
    ================
    
    Files Analyzed: #{length(results.files)}
    Total Issues: #{count_issues(results)}
    
    #{format_issues_summary(results)}
    """
  end
  
  defp format_analysis_table(results) do
    headers = ["File", "Issues", "Severity", "Type"]
    
    rows = results.files
    |> Enum.flat_map(fn file ->
      file.issues
      |> Enum.map(fn issue ->
        [file.path, issue.description, issue.severity, issue.type]
      end)
    end)
    
    TableRex.quick_render!(rows, headers)
  end
end
```

## 6. Client Adapters

### CLI Adapter
```elixir
defmodule RubberDuck.Commands.Adapters.CLI do
  def process_args(args, context) do
    RubberDuck.Commands.Parser.parse(args, :cli, context)
    |> case do
      {:ok, command} -> RubberDuck.Commands.Processor.execute(command)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### WebSocket Adapter
```elixir
defmodule RubberDuck.Commands.Adapters.WebSocket do
  def handle_message(%{"command" => command_data}, socket) do
    context = build_context_from_socket(socket)
    
    command_data
    |> RubberDuck.Commands.Parser.parse(:websocket, context)
    |> case do
      {:ok, command} ->
        case RubberDuck.Commands.Processor.execute(command) do
          {:ok, result} -> 
            Phoenix.Channel.push(socket, "command_result", %{
              status: "success", 
              data: result
            })
          {:error, reason} -> 
            Phoenix.Channel.push(socket, "command_error", %{
              status: "error", 
              reason: reason
            })
        end
        
      {:error, reason} ->
        Phoenix.Channel.push(socket, "command_error", %{
          status: "error", 
          reason: reason
        })
    end
  end
end
```

### LiveView Adapter
```elixir
defmodule RubberDuck.Commands.Adapters.LiveView do
  def handle_event("execute_command", params, socket) do
    context = build_context_from_socket(socket)
    
    case RubberDuck.Commands.Parser.parse(params, :liveview, context) do
      {:ok, command} ->
        case RubberDuck.Commands.Processor.execute(command) do
          {:ok, result} ->
            {:noreply, 
             socket 
             |> put_flash(:info, "Command executed successfully")
             |> assign(:command_result, result)}
             
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Command failed: #{reason}")}
        end
        
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Invalid command: #{reason}")}
    end
  end
end
```

## 7. Integration with Ash Framework

```elixir
defmodule RubberDuck.Commands.AshBridge do
  @moduledoc """
  Bridge between command system and Ash resources.
  """
  
  def execute_ash_action(command) do
    %{resource: resource, action: action, params: params} = 
      map_command_to_ash(command)
    
    resource
    |> Ash.Changeset.for_action(action, params)
    |> Ash.create(actor: command.context.user_id)
  end
  
  defp map_command_to_ash(%{name: :analyze} = command) do
    %{
      resource: RubberDuck.Workspace.AnalysisResult,
      action: :create,
      params: build_analysis_params(command)
    }
  end
  
  defp map_command_to_ash(%{name: :generate} = command) do
    %{
      resource: RubberDuck.Workspace.CodeFile,
      action: :create,
      params: build_generation_params(command)
    }
  end
end
```

## 8. Testing Strategy

```elixir
defmodule RubberDuck.Commands.ProcessorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Commands.{Command, Context, Processor}
  
  setup do
    context = %Context{
      user_id: "test_user",
      project_id: "test_project",
      session_id: "test_session",
      permissions: [:read, :write, :execute]
    }
    
    {:ok, context: context}
  end
  
  test "executes analyze command successfully", %{context: context} do
    command = %Command{
      name: :analyze,
      args: %{file_path: "test/fixtures/sample.ex"},
      options: %{recursive: false, format: "json"},
      context: context,
      client_type: :cli,
      format: :json
    }
    
    assert {:ok, result} = Processor.execute(command)
    assert Map.has_key?(result, "analysis_results")
  end
  
  test "handles unauthorized commands", %{context: context} do
    restricted_context = %{context | permissions: [:read]}
    
    command = %Command{
      name: :generate,
      args: %{description: "test code"},
      context: restricted_context,
      client_type: :cli,
      format: :text
    }
    
    assert {:error, "Unauthorized"} = Processor.execute(command)
  end
end
```

## Performance Considerations

1. **Command Caching**: Cache frequently used command validations and permissions
2. **Async Execution**: Long-running commands should spawn supervised tasks
3. **Rate Limiting**: Implement per-user rate limiting to prevent abuse
4. **Memory Management**: Commands should clean up temporary resources
5. **Telemetry**: Track command execution times and success rates

## Security Measures

1. **Input Validation**: All command inputs are validated before execution
2. **Authorization**: Commands check user permissions before execution  
3. **Sandboxing**: File operations are restricted to project directories
4. **Audit Logging**: All command executions are logged with user context
5. **Rate Limiting**: Prevent command flooding from any single user

This unified command abstraction layer provides the foundation for consistent, secure, and maintainable command processing across all RubberDuck client interfaces.
