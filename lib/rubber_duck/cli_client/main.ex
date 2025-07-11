defmodule RubberDuck.CLIClient.Main do
  @moduledoc """
  Main entry point for the RubberDuck CLI client.

  This module handles command-line parsing and routing to appropriate handlers.
  """

  alias RubberDuck.CLIClient.{Auth, UnifiedIntegration}

  @app_name "rubber_duck"
  @app_description "RubberDuck AI-powered coding assistant CLI"
  @app_version "0.1.0"

  def main(argv) do
    # Ensure we have the necessary applications started
    start_apps()

    # Parse and execute command
    case parse_args(argv) do
      {:ok, command, args, opts} ->
        execute_command(command, args, opts)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp start_apps do
    # Start required applications
    {:ok, _} = Application.ensure_all_started(:crypto)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:jason)
    {:ok, _} = Application.ensure_all_started(:phoenix_gen_socket_client)
  end

  defp parse_args(argv) do
    Optimus.new!(
      name: @app_name,
      description: @app_description,
      version: @app_version,
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        auth: auth_spec(),
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
          help: "Enable verbose output",
          multiple: false
        ],
        quiet: [
          short: "-q",
          long: "--quiet",
          help: "Suppress non-essential output",
          multiple: false
        ],
        debug: [
          long: "--debug",
          help: "Enable debug mode with detailed error information",
          multiple: false
        ]
      ],
      options: [
        format: [
          short: "-f",
          long: "--format",
          help: "Output format",
          parser: fn
            "json" -> {:ok, :json}
            "plain" -> {:ok, :plain}
            "table" -> {:ok, :table}
            other -> {:error, "Unknown format: #{other}. Supported: json, plain, table"}
          end,
          default: :plain,
          required: false
        ],
        server: [
          short: "-s",
          long: "--server",
          help: "RubberDuck server URL",
          parser: :string,
          required: false
        ]
      ]
    )
    |> Optimus.parse!(argv)
    |> extract_command()
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp extract_command(parsed) do
    case parsed do
      %{subcommand: nil} ->
        {:error, "No command specified. Run with --help for usage information."}

      # Handle nested subcommands (e.g., [:auth, :setup])
      {[cmd, subcmd], args} ->
        args_with_subcommand = Map.put(args, :subcommand, {subcmd, args})
        {:ok, cmd, args_with_subcommand, build_opts(args)}

      # Handle single command as list (e.g., [:health])
      {[cmd], args} ->
        {:ok, cmd, args, build_opts(args)}

      # Handle single command (e.g., :health)
      {cmd, args} when is_atom(cmd) ->
        {:ok, cmd, args, build_opts(args)}

      _ ->
        {:error, "Invalid command structure"}
    end
  end

  defp build_opts(parsed) do
    %{
      format: Map.get(parsed.options, :format, :plain),
      verbose: Map.get(parsed.flags, :verbose, false),
      quiet: Map.get(parsed.flags, :quiet, false),
      debug: Map.get(parsed.flags, :debug, false),
      server: Map.get(parsed.options, :server)
    }
  end

  defp execute_command(:auth, args, opts) do
    RubberDuck.CLIClient.Commands.Auth.run(args, opts)
  end

  defp execute_command(command, args, opts) do
    # Check if authenticated
    unless Auth.configured?() do
      IO.puts(:stderr, """
      Error: Not authenticated. Please run:
        #{@app_name} auth setup
      """)

      System.halt(1)
    end

    # Build configuration for unified integration
    config = %{
      user_id: Auth.get_user_id(),
      session_id: "cli_#{System.system_time(:millisecond)}",
      permissions: [:read, :write, :execute],
      format: opts[:format],
      server_url: opts[:server] || Auth.get_server_url(),
      metadata: %{
        cli_version: @app_version,
        verbose: opts[:verbose],
        debug: opts[:debug]
      }
    }

    # Convert Optimus parsed args to command line args format expected by unified parser
    unified_args = build_unified_args(command, args, opts)

    # Execute through unified integration
    case UnifiedIntegration.execute_command(unified_args, config) do
      {:ok, output} ->
        IO.puts(output)
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp build_unified_args(command, args, _opts) do
    # Convert Optimus parsed args back to command line format for unified parser
    base_args = [to_string(command)]
    
    # Add positional arguments based on command type
    args_list = case command do
      :analyze ->
        path = Map.get(args.args, :path)
        if path, do: base_args ++ [path], else: base_args
        
      :generate ->
        prompt = Map.get(args.args, :prompt)
        if prompt, do: base_args ++ [prompt], else: base_args
        
      :complete ->
        file = Map.get(args.args, :file)
        if file, do: base_args ++ [file], else: base_args
        
      :refactor ->
        file = Map.get(args.args, :file)
        if file, do: base_args ++ [file], else: base_args
        
      :test ->
        file = Map.get(args.args, :file)
        if file, do: base_args ++ [file], else: base_args
        
      :llm ->
        # LLM command has subcommands
        case Map.get(args, :subcommand) do
          {subcmd, _} -> base_args ++ [to_string(subcmd)]
          _ -> base_args
        end
        
      _ ->
        base_args
    end
    
    # Add options as flags
    options_list = args.options
    |> Enum.reduce([], fn {key, value}, acc ->
      case key do
        :type -> acc ++ ["--type", to_string(value)]
        :language -> acc ++ ["--language", to_string(value)]
        :framework -> acc ++ ["--framework", to_string(value)]
        :position -> acc ++ ["--position", to_string(value)]
        :instruction -> acc ++ ["--instruction", to_string(value)]
        :provider -> acc ++ ["--provider", to_string(value)]
        _ -> acc
      end
    end)
    
    # Add flags
    flags_list = args.flags
    |> Enum.reduce([], fn {key, true}, acc ->
      case key do
        :recursive -> acc ++ ["--recursive"]
        :verbose -> acc ++ ["--verbose"]
        :dry_run -> acc ++ ["--dry-run"]
        _ -> acc
      end
    end)
    
    args_list ++ options_list ++ flags_list
  end

  # Command specifications

  defp auth_spec do
    [
      name: "auth",
      about: "Manage authentication for RubberDuck CLI",
      subcommands: [
        setup: [
          name: "setup",
          about: "Set up authentication with RubberDuck server",
          options: [
            server: [
              long: "--server",
              value_name: "URL",
              help: "Server URL (default: ws://localhost:5555/socket/websocket)",
              parser: :string,
              required: false
            ]
          ]
        ],
        status: [
          name: "status",
          about: "Show authentication status"
        ],
        clear: [
          name: "clear",
          about: "Clear stored credentials"
        ]
      ]
    ]
  end

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
          parser: fn
            "all" -> {:ok, :all}
            "semantic" -> {:ok, :semantic}
            "style" -> {:ok, :style}
            "security" -> {:ok, :security}
            other -> {:error, "Unknown analysis type: #{other}"}
          end,
          default: :all,
          required: false
        ]
      ],
      flags: [
        recursive: [
          short: "-r",
          long: "--recursive",
          help: "Recursively analyze directories",
          multiple: false
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
          value_name: "PROMPT",
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
          default: "elixir",
          required: false
        ],
        output: [
          short: "-o",
          long: "--output",
          help: "Output file path",
          parser: :string,
          required: false
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
          help: "File to complete code in",
          required: true,
          parser: :string
        ]
      ],
      options: [
        line: [
          long: "--line",
          help: "Line number for completion",
          parser: :integer,
          required: true
        ],
        column: [
          long: "--column",
          help: "Column number for completion",
          parser: :integer,
          required: true
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
      ],
      flags: [
        dry_run: [
          long: "--dry-run",
          help: "Show changes without applying them",
          multiple: false
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
      ],
      options: [
        framework: [
          short: "-f",
          long: "--framework",
          help: "Test framework to use",
          parser: :string,
          default: "exunit",
          required: false
        ],
        output: [
          short: "-o",
          long: "--output",
          help: "Output file path for generated tests",
          parser: :string,
          required: false
        ]
      ]
    ]
  end

  defp llm_spec do
    [
      name: "llm",
      about: "Manage LLM provider connections",
      subcommands: [
        status: [
          name: "status",
          about: "Show LLM connection status"
        ],
        connect: [
          name: "connect",
          about: "Connect to an LLM provider",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name (e.g., mock, ollama, tgi)",
              required: false,
              parser: :string
            ]
          ]
        ],
        disconnect: [
          name: "disconnect",
          about: "Disconnect from an LLM provider",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name",
              required: false,
              parser: :string
            ]
          ]
        ],
        enable: [
          name: "enable",
          about: "Enable an LLM provider",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name",
              required: true,
              parser: :string
            ]
          ]
        ],
        disable: [
          name: "disable",
          about: "Disable an LLM provider",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name",
              required: true,
              parser: :string
            ]
          ]
        ]
      ]
    ]
  end

  defp health_spec do
    [
      name: "health",
      about: "Check RubberDuck server health status"
    ]
  end
end
