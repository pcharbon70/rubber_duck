defmodule RubberDuck.CLI do
  @moduledoc """
  Command-line interface for RubberDuck AI coding assistant.

  Provides a rich set of commands for code analysis, generation, completion,
  refactoring, and test generation.
  """

  @app_name "rubber_duck"
  @app_description "AI-powered coding assistant for Elixir developers"
  @app_version "0.1.0"

  alias RubberDuck.CLI.{Runner, Config}

  @doc """
  Parses command-line arguments and executes the appropriate command.
  """
  def main(argv) do
    Optimus.new!(
      name: @app_name,
      description: @app_description,
      version: @app_version,
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        analyze: analyze_spec(),
        generate: generate_spec(),
        complete: complete_spec(),
        refactor: refactor_spec(),
        test: test_spec(),
        llm: llm_spec()
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
        config: [
          short: "-c",
          long: "--config",
          help: "Path to configuration file",
          parser: :string,
          required: false
        ]
      ]
    )
    |> Optimus.parse!(argv)
    |> execute()
  rescue
    e ->
      # Optimus parse! exits the process, so we handle generic errors
      IO.puts(:stderr, "Error: #{Exception.message(e)}")
      System.halt(1)
  end

  defp execute(parsed) do
    # Handle different parse result formats
    {subcommand, subcommand_args, raw_parsed} =
      case parsed do
        # Nested subcommands return a tuple
        {subcommand_path, %Optimus.ParseResult{} = parse_result} ->
          # subcommand_path is a list like [:llm, :connect]
          [main_cmd | sub_cmds] = subcommand_path

          case sub_cmds do
            [] -> {main_cmd, parse_result.args, parse_result}
            [sub_cmd] -> {main_cmd, %{subcommand: {sub_cmd, parse_result.args}}, parse_result}
            _ -> {main_cmd, parse_result.args, parse_result}
          end

        # Regular commands return a ParseResult directly  
        %Optimus.ParseResult{} = parse_result ->
          cmd = Map.get(parse_result, :subcommand)
          {cmd, parse_result.args, parse_result}

        # Fallback
        _ ->
          {nil, %{}, %{}}
      end

    # Set up global configuration from parsed args
    config = Config.from_parsed_args(raw_parsed)

    # Execute the command
    result = Runner.run(subcommand, subcommand_args, config)

    case result do
      {:ok, _output} ->
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  # Command specifications

  defp analyze_spec do
    [
      name: "analyze",
      about: "Analyze code files or projects for issues, patterns, and improvements",
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
        ],
        include_suggestions: [
          long: "--include-suggestions",
          help: "Include fix suggestions in the output",
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
          help: "Natural language description of what to generate",
          required: true,
          parser: :string
        ]
      ],
      options: [
        output: [
          short: "-o",
          long: "--output",
          help: "Output file path (defaults to stdout)",
          parser: :string,
          required: false
        ],
        language: [
          short: "-l",
          long: "--language",
          help: "Target programming language",
          parser: :string,
          default: "elixir",
          required: false
        ],
        context: [
          long: "--context",
          help: "Path to context file or directory",
          parser: :string,
          required: false
        ]
      ],
      flags: [
        interactive: [
          short: "-i",
          long: "--interactive",
          help: "Enter interactive mode for iterative refinement",
          multiple: false
        ]
      ]
    ]
  end

  defp complete_spec do
    [
      name: "complete",
      about: "Get code completions for the current context",
      args: [
        file: [
          value_name: "FILE",
          help: "Path to the file being edited",
          required: true,
          parser: :string
        ]
      ],
      options: [
        line: [
          short: "-l",
          long: "--line",
          help: "Line number of cursor position",
          parser: :integer,
          required: true
        ],
        column: [
          short: "-c",
          long: "--column",
          help: "Column number of cursor position",
          parser: :integer,
          required: true
        ],
        max_suggestions: [
          short: "-n",
          long: "--max-suggestions",
          help: "Maximum number of suggestions to return",
          parser: :integer,
          default: 5,
          required: false
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
          help: "Path to the file to refactor",
          required: true,
          parser: :string
        ],
        instruction: [
          value_name: "INSTRUCTION",
          help: "Refactoring instruction or goal",
          required: true,
          parser: :string
        ]
      ],
      options: [
        output: [
          short: "-o",
          long: "--output",
          help: "Output file path (defaults to stdout)",
          parser: :string,
          required: false
        ]
      ],
      flags: [
        diff: [
          short: "-d",
          long: "--diff",
          help: "Show diff instead of full output",
          multiple: false
        ],
        in_place: [
          long: "--in-place",
          help: "Modify the file in place",
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
          help: "Path to the file to generate tests for",
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
      ],
      flags: [
        include_edge_cases: [
          long: "--include-edge-cases",
          help: "Generate tests for edge cases",
          multiple: false
        ],
        include_property_tests: [
          long: "--include-property-tests",
          help: "Generate property-based tests where applicable",
          multiple: false
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
              help: "Provider name (e.g., mock, ollama, tgi)",
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
              help: "Provider name (e.g., mock, ollama, tgi)",
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
              help: "Provider name (e.g., mock, ollama, tgi)",
              required: true,
              parser: :string
            ]
          ]
        ]
      ]
    ]
  end
end
