defmodule Mix.Tasks.RubberDuck.Help do
  @moduledoc """
  Show help information for RubberDuck CLI commands.

  ## Usage

      mix rubber_duck.help [topic]

  ## Topics

    * `commands` - List all available commands
    * `session` - Session management help
    * `config` - Configuration help
    * `examples` - Usage examples
    * `troubleshooting` - Common issues and solutions

  ## Examples

      # General help
      mix rubber_duck.help

      # Command-specific help
      mix rubber_duck.help commands

      # Session management help
      mix rubber_duck.help session

      # Configuration help
      mix rubber_duck.help config
  """

  use Mix.Task

  alias RubberDuck.Interface.CLI.ConfigManager

  @shortdoc "Show help for RubberDuck CLI"

  def run([]), do: show_general_help()
  def run(["--help"]), do: show_general_help()
  def run(["-h"]), do: show_general_help()
  def run([topic]), do: show_topic_help(topic)
  def run(_args), do: show_general_help()

  defp show_general_help do
    Mix.shell().info("""
    #{colorize("RubberDuck CLI", :cyan)} #{colorize("v1.0.0", :dim)}
    #{colorize("AI-powered coding assistant for the command line", :dim)}

    #{colorize("USAGE:", :bold)}
        mix rubber_duck.<command> [options]

    #{colorize("CORE COMMANDS:", :bold)}
        #{colorize("chat", :green)}                    Start interactive chat mode
        #{colorize("ask", :green)} <question>          Ask a direct question
        #{colorize("complete", :green)} <prompt>       Complete code or text

    #{colorize("SESSION COMMANDS:", :bold)}
        #{colorize("session.list", :cyan)}             List all sessions
        #{colorize("session.new", :cyan)} [name]       Create new session
        #{colorize("session.switch", :cyan)} <id>      Switch to session
        #{colorize("session.delete", :cyan)} <id>      Delete session

    #{colorize("CONFIG COMMANDS:", :bold)}
        #{colorize("config.show", :yellow)}            Show current configuration
        #{colorize("config.set", :yellow)} <k> <v>     Set configuration value
        #{colorize("config.reset", :yellow)}           Reset to defaults

    #{colorize("UTILITY COMMANDS:", :bold)}
        #{colorize("help", :magenta)} [topic]          Show help (this command)
        #{colorize("version", :magenta)}               Show version information
        #{colorize("status", :magenta)}                Show system status

    #{colorize("HELP TOPICS:", :bold)}
        #{colorize("commands", :dim)}                  Detailed command reference
        #{colorize("session", :dim)}                   Session management guide
        #{colorize("config", :dim)}                    Configuration options
        #{colorize("examples", :dim)}                  Usage examples
        #{colorize("troubleshooting", :dim)}           Common issues

    #{colorize("EXAMPLES:", :bold)}
        mix rubber_duck.chat
        mix rubber_duck.ask "How do I sort a list in Python?"
        mix rubber_duck.complete "def fibonacci(n):" --language python
        mix rubber_duck.help commands

    #{colorize("For detailed help on any command:", :dim)}
        mix help rubber_duck.<command>

    #{colorize("For topic-specific help:", :dim)}
        mix rubber_duck.help <topic>
    """)
  end

  defp show_topic_help(topic) do
    case topic do
      "commands" -> show_commands_help()
      "session" -> show_session_help()
      "config" -> show_config_help()
      "examples" -> show_examples_help()
      "troubleshooting" -> show_troubleshooting_help()
      _ -> 
        Mix.shell().error("Unknown help topic: #{topic}")
        Mix.shell().info("Available topics: commands, session, config, examples, troubleshooting")
    end
  end

  defp show_commands_help do
    Mix.shell().info("""
    #{colorize("COMMAND REFERENCE", :bold)}

    #{colorize("CHAT COMMANDS", :cyan)}

    #{colorize("mix rubber_duck.chat", :green)}
        Start interactive chat mode with real-time conversation.
        
        Options:
          --stream                Enable streaming responses
          --model <name>          Select AI model
          --session <id>          Use specific session
          --temperature <float>   Model creativity (0.0-2.0)
          --max-tokens <int>      Maximum response length
          --verbose               Show detailed output
          --quiet                 Minimal output mode

        Interactive commands:
          /help                   Show interactive help
          /session <action>       Session management
          /config <action>        Configuration management
          /clear                  Clear screen
          /exit                   Exit chat mode

    #{colorize("mix rubber_duck.ask", :green)} <question>
        Ask a direct question and get an immediate response.
        
        Options:
          --model <name>          Select AI model
          --session <id>          Use specific session
          --format <format>       Output format (text, json)
          --temperature <float>   Model creativity
          --max-tokens <int>      Maximum response length
          --verbose               Include metadata
          --quiet                 Response only

        Examples:
          mix rubber_duck.ask "Explain recursion"
          mix rubber_duck.ask "Best practices for Elixir" --verbose
          mix rubber_duck.ask "What is GraphQL?" --format json

    #{colorize("mix rubber_duck.complete", :green)} <prompt>
        Complete code or text using AI assistance.
        
        Options:
          --language <lang>       Programming language hint
          --model <name>          Select AI model
          --max-tokens <int>      Maximum completion length
          --temperature <float>   Creativity level (default: 0.3)
          --input <file>          Read prompt from file
          --output <file>         Write completion to file
          --append                Append to output file
          --verbose               Include metadata

        Examples:
          mix rubber_duck.complete "def fibonacci(n):" --language python
          mix rubber_duck.complete "SELECT * FROM" --language sql
          mix rubber_duck.complete --input prompt.txt --output result.py

    #{colorize("SESSION MANAGEMENT", :cyan)}

    #{colorize("mix rubber_duck.session.list", :yellow)}
        List all available sessions with creation and update times.

    #{colorize("mix rubber_duck.session.new", :yellow)} [name]
        Create a new session with optional name.
        
        Examples:
          mix rubber_duck.session.new
          mix rubber_duck.session.new "python-project"

    #{colorize("mix rubber_duck.session.switch", :yellow)} <id>
        Switch to an existing session.
        
        Example:
          mix rubber_duck.session.switch session_123

    #{colorize("mix rubber_duck.session.delete", :yellow)} <id>
        Delete a session and its history.
        
        Example:
          mix rubber_duck.session.delete session_123

    #{colorize("CONFIGURATION", :cyan)}

    #{colorize("mix rubber_duck.config.show", :yellow)}
        Display current configuration settings.

    #{colorize("mix rubber_duck.config.set", :yellow)} <key> <value>
        Set a configuration value.
        
        Examples:
          mix rubber_duck.config.set colors false
          mix rubber_duck.config.set model gpt-4
          mix rubber_duck.config.set temperature 0.7

    #{colorize("mix rubber_duck.config.reset", :yellow)}
        Reset all configuration to default values.

    #{colorize("UTILITY COMMANDS", :cyan)}

    #{colorize("mix rubber_duck.help", :magenta)} [topic]
        Show help information.

    #{colorize("mix rubber_duck.version", :magenta)}
        Show version and build information.

    #{colorize("mix rubber_duck.status", :magenta)}
        Show system status and health information.
    """)
  end

  defp show_session_help do
    Mix.shell().info("""
    #{colorize("SESSION MANAGEMENT", :bold)}

    Sessions allow you to maintain conversation context and history across
    multiple CLI invocations. Each session has its own conversation history,
    configuration, and state.

    #{colorize("CONCEPTS", :cyan)}

    #{colorize("Session ID", :yellow)}
        Unique identifier for each session (e.g., session_1234567890_abc)

    #{colorize("Session Name", :yellow)}
        Optional human-readable name for easier identification

    #{colorize("Session History", :yellow)}
        Complete conversation history maintained across CLI runs

    #{colorize("Session Context", :yellow)}
        AI model state and conversation context

    #{colorize("COMMANDS", :cyan)}

    #{colorize("Creating Sessions", :yellow)}
        mix rubber_duck.session.new                    # Auto-generated name
        mix rubber_duck.session.new "my-project"       # Custom name

    #{colorize("Listing Sessions", :yellow)}
        mix rubber_duck.session.list                   # Show all sessions

    #{colorize("Using Sessions", :yellow)}
        mix rubber_duck.chat --session my-project      # Use in chat mode
        mix rubber_duck.ask "question" --session id    # Use in direct mode

    #{colorize("Managing Sessions", :yellow)}
        mix rubber_duck.session.switch session_123     # Switch active session
        mix rubber_duck.session.delete session_123     # Delete session

    #{colorize("STORAGE", :cyan)}

    Sessions are stored locally in: #{colorize("~/.rubber_duck/sessions/", :dim)}
    
    Each session is saved as a JSON file containing:
    - Session metadata (ID, name, timestamps)
    - Conversation history
    - Configuration overrides
    - Context information

    #{colorize("BEST PRACTICES", :cyan)}

    - Use descriptive names for long-term projects
    - Create separate sessions for different projects or topics
    - Regularly clean up unused sessions
    - Use session switching for context management

    #{colorize("EXAMPLES", :cyan)}

    # Create a project-specific session
    mix rubber_duck.session.new "elixir-web-app"

    # Start chat in that session
    mix rubber_duck.chat --session elixir-web-app

    # Ask questions in the same context
    mix rubber_duck.ask "How do I add authentication?" --session elixir-web-app

    # List all sessions to see what's available
    mix rubber_duck.session.list

    # Switch between sessions
    mix rubber_duck.session.switch elixir-web-app
    mix rubber_duck.session.switch python-scripts
    """)
  end

  defp show_config_help do
    case ConfigManager.get_config_schema() do
      schema when is_map(schema) ->
        show_config_help_with_schema(schema)
      _ ->
        show_config_help_basic()
    end
  end

  defp show_config_help_with_schema(schema) do
    Mix.shell().info("""
    #{colorize("CONFIGURATION", :bold)}

    RubberDuck CLI can be configured through multiple sources:
    1. Environment variables (highest priority)
    2. User config file (~/.rubber_duck/config.yaml)
    3. Project config file (./rubber_duck.config.yaml)
    4. Default settings (lowest priority)

    #{colorize("COMMANDS", :cyan)}

    #{colorize("View Configuration", :yellow)}
        mix rubber_duck.config.show                    # Show current settings

    #{colorize("Update Configuration", :yellow)}
        mix rubber_duck.config.set <key> <value>       # Set single value
        mix rubber_duck.config.reset                   # Reset to defaults

    #{colorize("CONFIGURATION CATEGORIES", :cyan)}
    """)

    # Display each category from the schema
    Enum.each(schema, fn {category, settings} ->
      category_name = category |> to_string() |> String.upcase()
      Mix.shell().info("\n#{colorize(category_name, :yellow)}")
      
      Enum.each(settings, fn {key, config} ->
        key_name = colorize("#{key}", :cyan)
        type_info = colorize("(#{config.type})", :dim)
        default_info = colorize("default: #{inspect(config.default)}", :dim)
        
        Mix.shell().info("  #{key_name} #{type_info}")
        Mix.shell().info("    #{config.description}")
        Mix.shell().info("    #{default_info}")
        
        # Show valid values for enums
        if config[:values] do
          values_text = Enum.join(config.values, ", ")
          Mix.shell().info("    #{colorize("values: #{values_text}", :dim)}")
        end
        
        # Show range for numbers
        if config[:range] do
          {min, max} = config.range
          Mix.shell().info("    #{colorize("range: #{min} to #{max}", :dim)}")
        end
      end)
    end)

    Mix.shell().info("""

    #{colorize("ENVIRONMENT VARIABLES", :cyan)}

    RUBBER_DUCK_COLORS         Enable/disable colors (true/false)
    RUBBER_DUCK_MODEL          Default AI model
    RUBBER_DUCK_TEMPERATURE    Model temperature (0.0-2.0)
    RUBBER_DUCK_MAX_TOKENS     Maximum response tokens
    RUBBER_DUCK_TIMEOUT        Request timeout in milliseconds
    RUBBER_DUCK_LOG_LEVEL      Logging level (debug/info/warning/error)
    RUBBER_DUCK_CONFIG_DIR     Configuration directory path
    EDITOR                     Default editor command
    PAGER                      Default pager command

    #{colorize("EXAMPLES", :cyan)}

    # Set colors to false
    mix rubber_duck.config.set colors false

    # Change default model
    mix rubber_duck.config.set model gpt-4

    # Adjust temperature for more creative responses
    mix rubber_duck.config.set temperature 1.0

    # Set custom prompt
    mix rubber_duck.config.set interactive_prompt "AI > "

    # View all current settings
    mix rubber_duck.config.show

    # Reset everything to defaults
    mix rubber_duck.config.reset

    #{colorize("CONFIGURATION FILE EXAMPLE", :cyan)}

    # ~/.rubber_duck/config.yaml
    colors: true
    syntax_highlight: true
    model: claude
    temperature: 0.7
    max_tokens: 2048
    interactive_prompt: "🦆 > "
    """)
  end

  defp show_config_help_basic do
    Mix.shell().info("""
    #{colorize("CONFIGURATION", :bold)}

    Configuration commands and basic options.

    #{colorize("COMMANDS", :cyan)}
        mix rubber_duck.config.show     Show current configuration
        mix rubber_duck.config.set      Set configuration value
        mix rubber_duck.config.reset    Reset to defaults

    For detailed configuration help, ensure ConfigManager is properly loaded.
    """)
  end

  defp show_examples_help do
    Mix.shell().info("""
    #{colorize("USAGE EXAMPLES", :bold)}

    #{colorize("GETTING STARTED", :cyan)}

    # Start with basic question
    mix rubber_duck.ask "What is Elixir?"

    # Enter interactive mode
    mix rubber_duck.chat

    # Complete some code
    mix rubber_duck.complete "def hello" --language elixir

    #{colorize("PROJECT WORKFLOW", :cyan)}

    # Create a project session
    mix rubber_duck.session.new "my-web-app"

    # Use that session for related questions
    mix rubber_duck.ask "How do I add Phoenix to my project?" --session my-web-app
    mix rubber_duck.ask "What's the best way to handle authentication?" --session my-web-app

    # Start interactive chat in that session
    mix rubber_duck.chat --session my-web-app

    #{colorize("CODE COMPLETION", :cyan)}

    # Complete Python function
    mix rubber_duck.complete "def quicksort(arr):" --language python

    # Complete SQL query
    mix rubber_duck.complete "SELECT users.name, COUNT(" --language sql

    # Complete from file and save to file
    mix rubber_duck.complete --input partial.py --output complete.py --language python

    #{colorize("DIFFERENT OUTPUT FORMATS", :cyan)}

    # Get response as JSON
    mix rubber_duck.ask "Explain microservices" --format json

    # Quiet mode (just the answer)
    mix rubber_duck.ask "What is 2+2?" --quiet

    # Verbose mode (include metadata)
    mix rubber_duck.ask "Explain async/await" --verbose

    #{colorize("ADVANCED USAGE", :cyan)}

    # Use specific model with custom temperature
    mix rubber_duck.ask "Write a creative story" --model gpt-4 --temperature 1.5

    # Stream responses in real-time
    mix rubber_duck.chat --stream

    # Complete with specific token limit
    mix rubber_duck.complete "class Calculator:" --language python --max-tokens 200

    #{colorize("CONFIGURATION EXAMPLES", :cyan)}

    # Disable colors for scripts
    mix rubber_duck.config.set colors false

    # Set your preferred model
    mix rubber_duck.config.set model claude

    # Customize the chat prompt
    mix rubber_duck.config.set interactive_prompt "Assistant > "

    #{colorize("TROUBLESHOOTING EXAMPLES", :cyan)}

    # Check system status
    mix rubber_duck.status

    # Get help for specific command
    mix help rubber_duck.ask

    # View current configuration
    mix rubber_duck.config.show

    # Reset configuration if something's wrong
    mix rubber_duck.config.reset

    #{colorize("INTEGRATION EXAMPLES", :cyan)}

    # Use in shell scripts
    ANSWER=$(mix rubber_duck.ask "How to exit vim?" --quiet)
    echo "The answer is: $ANSWER"

    # Pipe input
    echo "def fibonacci" | mix rubber_duck.complete --language python

    # Process files
    mix rubber_duck.complete --input todo.py --output complete.py --language python
    """)
  end

  defp show_troubleshooting_help do
    Mix.shell().info("""
    #{colorize("TROUBLESHOOTING", :bold)}

    #{colorize("COMMON ISSUES", :cyan)}

    #{colorize("Command not found", :yellow)}
        Problem: mix rubber_duck.* commands not available
        Solution: Ensure the project is compiled: mix compile
        
    #{colorize("Configuration errors", :yellow)}
        Problem: Invalid configuration values
        Solution: Reset configuration: mix rubber_duck.config.reset
        
    #{colorize("Session not found", :yellow)}
        Problem: Cannot find specified session
        Solution: List available sessions: mix rubber_duck.session.list

    #{colorize("Timeout errors", :yellow)}
        Problem: Requests timing out
        Solution: Increase timeout: mix rubber_duck.config.set timeout 60000

    #{colorize("No response from AI", :yellow)}
        Problem: Empty or error responses
        Solution: Check status: mix rubber_duck.status

    #{colorize("Colors not working", :yellow)}
        Problem: ANSI colors not displaying
        Solution: Check terminal support or disable: mix rubber_duck.config.set colors false

    #{colorize("File permission errors", :yellow)}
        Problem: Cannot write to config directory
        Solution: Check permissions on ~/.rubber_duck/ directory

    #{colorize("DIAGNOSTIC COMMANDS", :cyan)}

    # Check overall system status
    mix rubber_duck.status

    # View current configuration
    mix rubber_duck.config.show

    # List available sessions
    mix rubber_duck.session.list

    # Test basic functionality
    mix rubber_duck.ask "Hello" --verbose

    # Check Mix task availability
    mix help | grep rubber_duck

    #{colorize("ENVIRONMENT DEBUGGING", :cyan)}

    # Check Elixir/Mix installation
    elixir --version
    mix --version

    # Check if project compiles
    mix compile

    # Check dependencies
    mix deps.get

    # Run with verbose output
    mix rubber_duck.ask "test" --verbose

    #{colorize("LOG FILES", :cyan)}

    Default log location: ~/.rubber_duck/logs/
    Session files: ~/.rubber_duck/sessions/
    Configuration: ~/.rubber_duck/config.yaml

    # Enable debug logging
    mix rubber_duck.config.set log_level debug

    #{colorize("RESET PROCEDURES", :cyan)}

    # Reset configuration only
    mix rubber_duck.config.reset

    # Clear all sessions (be careful!)
    rm -rf ~/.rubber_duck/sessions/*

    # Complete reset (nuclear option)
    rm -rf ~/.rubber_duck/

    #{colorize("GETTING HELP", :cyan)}

    # Command-specific help
    mix help rubber_duck.ask
    mix help rubber_duck.chat
    mix help rubber_duck.complete

    # General help
    mix rubber_duck.help

    # Specific topic help
    mix rubber_duck.help commands
    mix rubber_duck.help session
    mix rubber_duck.help config

    #{colorize("REPORTING ISSUES", :cyan)}

    When reporting issues, please include:
    - Output of: mix rubber_duck.status
    - Output of: mix rubber_duck.config.show
    - The exact command that failed
    - Full error message
    - Operating system and terminal information
    """)
  end

  defp colorize(text, color) do
    case color do
      :bold -> "\e[1m#{text}\e[0m"
      :dim -> "\e[2m#{text}\e[0m"
      :cyan -> "\e[36m#{text}\e[0m"
      :green -> "\e[32m#{text}\e[0m"
      :yellow -> "\e[33m#{text}\e[0m"
      :magenta -> "\e[35m#{text}\e[0m"
      _ -> text
    end
  end
end