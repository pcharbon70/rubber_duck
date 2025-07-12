defmodule RubberDuck.Commands.Parser do
  @moduledoc """
  Unified command parser that converts client-specific input into 
  standardized Command structs.
  
  Supports parsing from:
  - CLI arguments using Optimus
  - WebSocket messages
  - LiveView parameters
  - TUI input
  """

  alias RubberDuck.Commands.{Command, Context}

  @doc """
  Parses input from any client type into a standardized Command struct.
  """
  def parse(input, client_type, context) do
    case client_type do
      :cli -> parse_cli_input(input, context)
      :websocket -> parse_websocket_message(input, context)
      :liveview -> parse_liveview_params(input, context)
      :tui -> parse_tui_input(input, context)
    end
  end

  # CLI parsing using Optimus
  defp parse_cli_input(args, context) do
    try do
      parsed = optimus_spec() |> Optimus.parse!(args)
      
      case extract_command_from_parsed(parsed) do
        {:ok, name, command_args, options} ->
          format = determine_format(options, :cli)
          
          Command.new(%{
            name: name,
            args: command_args,
            options: options,
            context: context,
            client_type: :cli,
            format: format
          })
          
        error -> error
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # WebSocket message parsing
  defp parse_websocket_message(%{"command" => command_name} = message, context) do
    try do
      name = String.to_atom(command_name)
      args = Map.get(message, "args", %{}) |> atomize_keys()
      options = Map.get(message, "options", %{}) |> atomize_keys()
      format = determine_format(options, :websocket)
      
      Command.new(%{
        name: name,
        args: args,
        options: options,
        context: context,
        client_type: :websocket,
        format: format
      })
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp parse_websocket_message(_, _), do: {:error, "Invalid WebSocket message format"}

  # LiveView params parsing
  defp parse_liveview_params(%{"command" => command_name} = params, context) do
    try do
      name = String.to_atom(command_name)
      {args, options} = extract_liveview_args_and_options(params, name)
      format = determine_format(options, :liveview)
      
      Command.new(%{
        name: name,
        args: args,
        options: options,
        context: context,
        client_type: :liveview,
        format: format
      })
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp parse_liveview_params(_, _), do: {:error, "Invalid LiveView params format"}

  # TUI input parsing (similar to CLI for now)
  defp parse_tui_input(input, context) when is_list(input) do
    parse_cli_input(input, context)
  end
  
  defp parse_tui_input(_, _), do: {:error, "Invalid TUI input format"}

  # Extract command from Optimus parsed result
  defp extract_command_from_parsed(%{subcommand: nil}), do: {:error, "No command specified"}
  
  defp extract_command_from_parsed({[name], parsed}) do
    args = extract_args(parsed, name)
    options = extract_options(parsed)
    {:ok, name, args, options}
  end
  
  defp extract_command_from_parsed({[name, _subcmd], parsed}) do
    args = extract_args(parsed, name)
    options = extract_options(parsed)
    {:ok, name, args, options}
  end

  # Extract arguments based on command type
  defp extract_args(%{args: args}, :analyze) do
    %{path: Map.get(args, :path)}
  end
  
  defp extract_args(%{args: args}, :generate) do
    %{description: Map.get(args, :prompt)}
  end
  
  defp extract_args(%{args: args}, :complete) do
    %{
      file: Map.get(args, :file),
      position: Map.get(args, :position)
    }
  end
  
  defp extract_args(%{args: args}, :refactor) do
    %{
      file: Map.get(args, :file),
      instruction: Map.get(args, :instruction)
    }
  end
  
  defp extract_args(%{args: args}, :test) do
    %{file: Map.get(args, :file)}
  end
  
  defp extract_args(%{args: args}, :llm) do
    %{action: Map.get(args, :action)}
  end
  
  defp extract_args(%{args: _args}, :health) do
    %{}
  end
  
  defp extract_args(_, _), do: %{}

  # Extract options from parsed result
  defp extract_options(%{options: options, flags: flags}) do
    Map.merge(options, flags)
  end

  # Extract args and options for LiveView
  defp extract_liveview_args_and_options(params, :generate) do
    args = %{description: Map.get(params, "description")}
    options = Map.take(params, ["language", "output"]) |> atomize_keys()
    {args, options}
  end
  
  defp extract_liveview_args_and_options(params, :analyze) do
    args = %{path: Map.get(params, "path")}
    options = Map.take(params, ["type", "recursive"]) |> atomize_keys()
    {args, options}
  end
  
  defp extract_liveview_args_and_options(params, _command) do
    # Generic extraction - separate known arg fields from options
    args = Map.take(params, ["description", "path", "file", "instruction", "action"])
           |> atomize_keys()
    options = Map.drop(params, ["command", "description", "path", "file", "instruction", "action"])
              |> atomize_keys()
    {args, options}
  end

  # Determine output format based on client type and options
  defp determine_format(options, :cli) do
    case Map.get(options, :format) do
      :json -> :json
      :table -> :table
      _ -> :text
    end
  end
  
  defp determine_format(_options, :websocket), do: :json
  defp determine_format(_options, :liveview), do: :markdown
  defp determine_format(_options, :tui), do: :text

  # Helper to convert string keys to atoms
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  # Optimus specification (based on existing CLI client)
  defp optimus_spec do
    Optimus.new!(
      name: "rubber_duck",
      description: "AI-powered coding assistant",
      version: "1.0.0",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        analyze: analyze_spec(),
        generate: generate_spec(),
        complete: complete_spec(),
        refactor: refactor_spec(),
        test: test_spec(),
        llm: llm_spec(),
        health: health_spec()
      ],
      flags: [
        verbose: [
          short: "-v",
          long: "--verbose",
          help: "Enable verbose output"
        ]
      ],
      options: [
        format: [
          short: "-f",
          long: "--format",
          help: "Output format",
          parser: fn
            "json" -> {:ok, :json}
            "text" -> {:ok, :text}
            "table" -> {:ok, :table}
            other -> {:error, "Unknown format: #{other}"}
          end,
          default: :text
        ]
      ]
    )
  end

  # Command specifications
  defp analyze_spec do
    [
      name: "analyze",
      about: "Analyze code files or projects",
      args: [
        path: [
          value_name: "PATH",
          help: "Path to file or directory to analyze",
          required: true,
          parser: :string
        ]
      ],
      options: [
        type: [
          short: "-t",
          long: "--type",
          help: "Type of analysis to perform",
          parser: :string,
          default: "all"
        ]
      ],
      flags: [
        recursive: [
          short: "-r",
          long: "--recursive",
          help: "Recursively analyze directories"
        ]
      ]
    ]
  end

  defp generate_spec do
    [
      name: "generate",
      about: "Generate code from natural language descriptions",
      args: [
        prompt: [
          value_name: "DESCRIPTION",
          help: "Natural language description of code to generate",
          required: true,
          parser: :string
        ]
      ],
      options: [
        language: [
          short: "-l",
          long: "--language",
          help: "Target programming language",
          parser: :string,
          default: "elixir"
        ]
      ]
    ]
  end

  defp complete_spec do
    [
      name: "complete",
      about: "Get code completions",
      args: [
        file: [
          value_name: "FILE",
          help: "File to complete",
          required: true,
          parser: :string
        ],
        position: [
          value_name: "POSITION",
          help: "Cursor position (line:column)",
          required: true,
          parser: :string
        ]
      ]
    ]
  end

  defp refactor_spec do
    [
      name: "refactor",
      about: "Refactor code with AI assistance",
      args: [
        file: [
          value_name: "FILE",
          help: "File to refactor",
          required: true,
          parser: :string
        ],
        instruction: [
          value_name: "INSTRUCTION",
          help: "Refactoring instruction",
          required: true,
          parser: :string
        ]
      ]
    ]
  end

  defp test_spec do
    [
      name: "test",
      about: "Generate tests for existing code",
      args: [
        file: [
          value_name: "FILE",
          help: "File to generate tests for",
          required: true,
          parser: :string
        ]
      ]
    ]
  end

  defp llm_spec do
    [
      name: "llm",
      about: "Manage LLM providers",
      args: [
        action: [
          value_name: "ACTION",
          help: "Action to perform (list, status, configure)",
          required: true,
          parser: :string
        ]
      ]
    ]
  end

  defp health_spec do
    [
      name: "health",
      about: "Check system health"
    ]
  end
end