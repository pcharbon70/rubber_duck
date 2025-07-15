defmodule RubberDuck.CLIClient.Main do
  @moduledoc """
  Main entry point for the RubberDuck CLI client.

  This module handles command-line parsing and routing to appropriate handlers.
  """

  alias RubberDuck.CLIClient.{Auth, UnifiedIntegration}
  require Logger

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
    
    # Configure logger for CLI
    Logger.configure(level: :warning)
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
        health: health_spec(),
        conversation: conversation_spec(),
        repl: repl_spec()
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

  defp execute_command(:conversation, args, opts) do
    # Check if authenticated first
    unless Auth.configured?() do
      IO.puts(:stderr, """
      Error: Not authenticated. Please run:
        #{@app_name} auth setup
      """)
      System.halt(1)
    end

    # Handle chat subcommand specially for interactive mode
    case Map.get(args, :subcommand) do
      {:chat, chat_args} ->
        RubberDuck.CLIClient.ConversationHandler.run_chat(chat_args, opts)
      
      _ ->
        # Other conversation subcommands go through unified integration
        execute_unified_command(:conversation, args, opts)
    end
  end

  defp execute_command(:repl, args, opts) do
    # Check if authenticated first
    unless Auth.configured?() do
      IO.puts(:stderr, """
      Error: Not authenticated. Please run:
        #{@app_name} auth setup
      """)
      System.halt(1)
    end

    # Delegate to REPL handler
    RubberDuck.CLIClient.REPLHandler.run(args, opts)
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

    execute_unified_command(command, args, opts)
  end

  defp execute_unified_command(command, args, opts) do
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
      {:ok, output} when is_binary(output) ->
        IO.puts(output)
        System.halt(0)
        
      {:ok, output} ->
        # Handle non-string outputs (e.g., maps, lists)
        IO.puts(inspect(output, pretty: true))
        System.halt(0)

      {:error, reason} when is_binary(reason) ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
        
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
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
        instruction = Map.get(args.args, :instruction)
        base_with_file = if file, do: base_args ++ [file], else: base_args
        if instruction, do: base_with_file ++ [instruction], else: base_with_file
        
      :test ->
        file = Map.get(args.args, :file)
        if file, do: base_args ++ [file], else: base_args
        
      :llm ->
        # LLM command has subcommands
        case Map.get(args, :subcommand) do
          {subcmd, subcmd_args} -> 
            subcmd_base = base_args ++ [to_string(subcmd)]
            # Add subcommand-specific args
            case subcmd do
              :connect ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              :disconnect ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              :enable ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              :disable ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              :set_model ->
                arg1 = Map.get(subcmd_args.args, :arg1)
                arg2 = Map.get(subcmd_args.args, :arg2)
                args_list = if arg1, do: subcmd_base ++ [arg1], else: subcmd_base
                if arg2, do: args_list ++ [arg2], else: args_list
              :list_models ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              :set_default ->
                provider = Map.get(subcmd_args.args, :provider)
                if provider, do: subcmd_base ++ [provider], else: subcmd_base
              _ ->
                subcmd_base
            end
          _ -> base_args
        end
        
      :conversation ->
        # Conversation command has subcommands
        case Map.get(args, :subcommand) do
          {subcmd, subcmd_args} -> 
            subcmd_base = base_args ++ [to_string(subcmd)]
            # Add subcommand-specific args
            case subcmd do
              :start ->
                title = Map.get(subcmd_args.args, :title)
                if title, do: subcmd_base ++ [title], else: subcmd_base
              :show ->
                id = Map.get(subcmd_args.args, :conversation_id)
                if id, do: subcmd_base ++ [id], else: subcmd_base
              :send ->
                message = Map.get(subcmd_args.args, :message)
                if message, do: subcmd_base ++ [message], else: subcmd_base
              :delete ->
                id = Map.get(subcmd_args.args, :conversation_id)
                if id, do: subcmd_base ++ [id], else: subcmd_base
              :chat ->
                id = Map.get(subcmd_args.args, :conversation_id)
                if id, do: subcmd_base ++ [id], else: subcmd_base
              _ ->
                subcmd_base
            end
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
        :conversation -> acc ++ ["--conversation", to_string(value)]
        :title -> acc ++ ["--title", to_string(value)]
        :line -> acc ++ ["--line", to_string(value)]
        :column -> acc ++ ["--column", to_string(value)]
        :output -> acc ++ ["--output", to_string(value)]
        :max_suggestions -> acc ++ ["--max", to_string(value)]
        :context -> acc ++ ["--context", to_string(value)]
        _ -> acc
      end
    end)
    
    # Add flags
    flags_list = args.flags
    |> Enum.reduce([], fn 
      {key, true}, acc ->
        case key do
          :recursive -> acc ++ ["--recursive"]
          :verbose -> acc ++ ["--verbose"]
          :dry_run -> acc ++ ["--dry-run"]
          :include_suggestions -> acc ++ ["--include-suggestions"]
          :include_edge_cases -> acc ++ ["--include-edge-cases"]
          :include_property_tests -> acc ++ ["--include-property-tests"]
          :diff -> acc ++ ["--diff"]
          :in_place -> acc ++ ["--in-place"]
          :interactive -> acc ++ ["--interactive"]
          :no_cache -> acc ++ ["--no-cache"]
          _ -> acc
        end
      {_key, false}, acc ->
        # Skip false flags
        acc
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
        ],
        set_model: [
          name: "set_model",
          about: "Set the LLM model to use. Usage: set_model <model> OR set_model <provider> <model>",
          args: [
            arg1: [
              value_name: "MODEL_OR_PROVIDER",
              help: "Model name (if only one arg) or Provider name (if two args)",
              required: true,
              parser: :string
            ],
            arg2: [
              value_name: "MODEL",
              help: "Model name (when provider is specified)",
              required: false,
              parser: :string
            ]
          ]
        ],
        list_models: [
          name: "list_models",
          about: "List available LLM models",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name (optional - if not specified, lists all models)",
              required: false,
              parser: :string
            ]
          ]
        ],
        set_default: [
          name: "set_default",
          about: "Set the default LLM provider",
          args: [
            provider: [
              value_name: "PROVIDER",
              help: "Provider name to set as default",
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

  defp conversation_spec do
    [
      name: "conversation",
      about: "Manage AI conversations",
      subcommands: [
        start: [
          name: "start",
          about: "Start a new conversation",
          args: [
            title: [
              value_name: "TITLE",
              help: "Title for the conversation",
              required: false,
              parser: :string
            ]
          ],
          options: [
            type: [
              short: "-t",
              long: "--type",
              help: "Type of conversation (general, coding, debugging, planning, review)",
              parser: fn
                t when t in ["general", "coding", "debugging", "planning", "review"] -> 
                  {:ok, t}
                other -> 
                  {:error, "Invalid conversation type: #{other}"}
              end,
              default: "general",
              required: false
            ]
          ]
        ],
        list: [
          name: "list",
          about: "List all conversations"
        ],
        show: [
          name: "show",
          about: "Show conversation details and history",
          args: [
            conversation_id: [
              value_name: "ID",
              help: "Conversation ID",
              required: true,
              parser: :string
            ]
          ]
        ],
        send: [
          name: "send",
          about: "Send a message to a conversation",
          args: [
            message: [
              value_name: "MESSAGE",
              help: "Message to send",
              required: true,
              parser: :string
            ]
          ],
          options: [
            conversation: [
              short: "-c",
              long: "--conversation",
              help: "Conversation ID",
              parser: :string,
              required: true
            ]
          ]
        ],
        delete: [
          name: "delete",
          about: "Delete a conversation",
          args: [
            conversation_id: [
              value_name: "ID",
              help: "Conversation ID to delete",
              required: true,
              parser: :string
            ]
          ]
        ],
        chat: [
          name: "chat",
          about: "Enter interactive chat mode",
          args: [
            conversation_id: [
              value_name: "ID",
              help: "Conversation ID (optional, creates new if not provided)",
              required: false,
              parser: :string
            ]
          ],
          options: [
            title: [
              short: "-t",
              long: "--title",
              help: "Title for new conversation",
              parser: :string,
              required: false
            ]
          ]
        ]
      ]
    ]
  end

  defp repl_spec do
    [
      name: "repl",
      about: "Start an interactive REPL session with the AI assistant",
      options: [
        type: [
          short: "-t",
          long: "--type",
          help: "Type of conversation (general, coding, debugging, planning, review)",
          parser: fn
            t when t in ["general", "coding", "debugging", "planning", "review"] -> 
              {:ok, t}
            other -> 
              {:error, "Invalid conversation type: #{other}"}
          end,
          default: "general",
          required: false
        ],
        model: [
          short: "-m",
          long: "--model",
          help: "Specific model to use for the conversation",
          parser: :string,
          required: false
        ],
        resume: [
          short: "-r",
          long: "--resume",
          help: "Resume last conversation or specify conversation ID",
          parser: :string,
          required: false
        ]
      ],
      flags: [
        no_welcome: [
          long: "--no-welcome",
          help: "Skip welcome message",
          multiple: false
        ]
      ]
    ]
  end
end
