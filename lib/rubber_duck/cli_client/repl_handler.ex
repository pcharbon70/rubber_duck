defmodule RubberDuck.CLIClient.REPLHandler do
  @moduledoc """
  Enhanced REPL handler for interactive AI conversations.
  
  Provides a rich REPL experience with multi-line input, context management,
  session persistence, and integrated commands.
  """

  alias RubberDuck.CLIClient.{Auth, Client, ConversationHandler}
  require Logger

  @prompt "rd> "
  @continuation_prompt "... "
  @assistant_prefix "🤖 "
  @user_prefix "👤 "
  @system_prefix "ℹ️  "
  @error_prefix "❌ "
  @success_prefix "✅ "

  # Session state
  defmodule State do
    @moduledoc false
    defstruct [
      :conversation_id,
      :conversation_type,
      :model,
      :context_files,
      :history,
      :multiline_buffer,
      :last_save_time,
      :opts
    ]
  end

  @doc """
  Runs the enhanced REPL session.
  """
  def run(args, opts) do
    # Initialize state
    state = %State{
      conversation_type: Map.get(args.options, :type, "general"),
      model: Map.get(args.options, :model),
      context_files: [],
      history: [],
      multiline_buffer: [],
      last_save_time: System.system_time(:second),
      opts: opts
    }

    # Ensure client is started
    ensure_client_started(opts)

    # Check LLM connection
    check_llm_connection()

    # Handle resume option
    state = handle_resume_option(state, args)

    # Show welcome unless disabled
    unless Map.get(args.flags, :no_welcome, false) do
      show_welcome(state)
    end

    # Start the REPL loop
    repl_loop(state)
  end

  defp ensure_client_started(opts) do
    case Process.whereis(RubberDuck.CLIClient.Client) do
      nil ->
        server_url = opts[:server] || Auth.get_server_url()
        api_key = Auth.get_api_key()
        
        {:ok, _pid} = Client.start_link(url: server_url, api_key: api_key)
        
        # Actually connect to the server
        case Client.connect(server_url) do
          {:ok, _} -> 
            wait_for_connection()
          {:error, reason} ->
            IO.puts(:stderr, "#{@error_prefix}Failed to connect to server: #{reason}")
            System.halt(1)
        end
        
      _pid ->
        # Check if already connected
        case Client.connected?() do
          true -> :ok
          false ->
            server_url = opts[:server] || Auth.get_server_url()
            case Client.connect(server_url) do
              {:ok, _} -> 
                wait_for_connection()
              {:error, reason} ->
                IO.puts(:stderr, "#{@error_prefix}Failed to connect to server: #{reason}")
                System.halt(1)
            end
        end
    end
  end
  
  defp wait_for_connection(attempts \\ 0) do
    if attempts >= 20 do  # 10 seconds max
      IO.puts(:stderr, "#{@error_prefix}Timeout waiting for WebSocket connection")
      System.halt(1)
    end
    
    case Client.connected?() do
      true -> :ok
      false ->
        Process.sleep(500)
        wait_for_connection(attempts + 1)
    end
  end

  defp check_llm_connection do
    case send_command(["llm", "status"]) do
      {:ok, status} ->
        unless String.contains?(status, "connected") && 
               not String.contains?(status, "No providers") do
          IO.puts(:stderr, """
          #{@error_prefix}No LLM provider is connected.
          
          Please connect an LLM provider first using:
            rubber_duck llm connect <provider>
          """)
          System.halt(1)
        end
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error checking LLM status: #{reason}")
        System.halt(1)
    end
  end

  defp handle_resume_option(state, args) do
    case Map.get(args.options, :resume) do
      nil -> 
        # No resume option, create new conversation
        create_new_conversation(state)
        
      "last" ->
        # Resume last conversation
        resume_last_conversation(state)
        
      conversation_id ->
        # Resume specific conversation
        resume_conversation(state, conversation_id)
    end
  end

  defp create_new_conversation(state) do
    title = "REPL Session - #{format_timestamp()}"
    
    case send_command(["conversation", "start", title, "--type", state.conversation_type]) do
      {:ok, response} ->
        case ConversationHandler.extract_conversation_id(response) do
          {:ok, id} ->
            IO.puts("#{@success_prefix}Started new conversation: #{id}")
            %{state | conversation_id: id}
          {:error, _} ->
            IO.puts(:stderr, "#{@error_prefix}Failed to create conversation")
            System.halt(1)
        end
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error: #{reason}")
        System.halt(1)
    end
  end

  defp resume_last_conversation(state) do
    case send_command(["conversation", "list"]) do
      {:ok, output} ->
        # Extract first conversation ID from the list
        case extract_first_conversation_id(output) do
          {:ok, id} ->
            IO.puts("#{@system_prefix}Resuming conversation: #{id}")
            %{state | conversation_id: id}
          {:error, _} ->
            IO.puts("#{@system_prefix}No previous conversations found. Starting new session.")
            create_new_conversation(state)
        end
      {:error, _} ->
        create_new_conversation(state)
    end
  end

  defp resume_conversation(state, conversation_id) do
    case send_command(["conversation", "show", conversation_id]) do
      {:ok, _} ->
        IO.puts("#{@success_prefix}Resumed conversation: #{conversation_id}")
        %{state | conversation_id: conversation_id}
      {:error, _} ->
        IO.puts(:stderr, "#{@error_prefix}Conversation not found: #{conversation_id}")
        System.halt(1)
    end
  end

  defp repl_loop(state) do
    # Auto-save periodically
    state = maybe_auto_save(state)

    # Get input with proper prompt
    prompt = if state.multiline_buffer == [], do: @prompt, else: @continuation_prompt
    
    case IO.gets(prompt) do
      :eof ->
        handle_exit(state)
        
      {:error, reason} ->
        IO.puts(:stderr, "\n#{@error_prefix}Error reading input: #{inspect(reason)}")
        System.halt(1)
        
      input ->
        input = String.trim_trailing(input, "\n")
        state = handle_input(state, input)
        repl_loop(state)
    end
  end

  defp handle_input(state, input) do
    cond do
      # Check for multiline start
      String.starts_with?(input, "\"\"\"") ->
        start_multiline(state, String.trim_leading(input, "\"\"\""))
        
      # Check for multiline end
      state.multiline_buffer != [] && String.ends_with?(input, "\"\"\"") ->
        end_multiline(state, String.trim_trailing(input, "\"\"\""))
        
      # Continue multiline
      state.multiline_buffer != [] ->
        %{state | multiline_buffer: state.multiline_buffer ++ [input]}
        
      # Line continuation
      String.ends_with?(input, "\\") ->
        line = String.trim_trailing(input, "\\")
        %{state | multiline_buffer: [line]}
        
      # Single line command
      true ->
        process_command(state, input)
    end
  end

  defp start_multiline(state, first_line) do
    lines = if first_line == "", do: [], else: [first_line]
    %{state | multiline_buffer: lines}
  end

  defp end_multiline(state, last_line) do
    lines = if last_line == "", 
      do: state.multiline_buffer, 
      else: state.multiline_buffer ++ [last_line]
    
    message = Enum.join(lines, "\n")
    state = %{state | multiline_buffer: []}
    process_command(state, message)
  end

  defp process_command(state, "") do
    # Empty input, just return
    state
  end

  defp process_command(state, "/" <> command) do
    # Handle slash commands
    handle_slash_command(state, String.split(command, " ", parts: 2))
  end

  defp process_command(state, message) do
    # Regular message - send to conversation
    send_message(state, message)
  end

  defp handle_slash_command(state, ["help"]) do
    show_help()
    state
  end

  defp handle_slash_command(state, ["exit"]) do
    handle_exit(state)
  end

  defp handle_slash_command(state, ["clear"]) do
    clear_screen()
    state
  end

  defp handle_slash_command(state, ["history"]) do
    show_history(state)
    state
  end

  defp handle_slash_command(state, ["save", filename]) do
    save_conversation(state, filename)
  end

  defp handle_slash_command(state, ["save"]) do
    filename = "conversation_#{state.conversation_id}_#{System.system_time(:second)}.md"
    save_conversation(state, filename)
  end

  defp handle_slash_command(state, ["context", "add", file_path]) do
    add_context_file(state, file_path)
  end

  defp handle_slash_command(state, ["context", "clear"]) do
    IO.puts("#{@success_prefix}Context cleared")
    %{state | context_files: []}
  end

  defp handle_slash_command(state, ["context"]) do
    show_context(state)
    state
  end

  defp handle_slash_command(state, ["model", model_spec]) do
    change_model(state, model_spec)
  end

  defp handle_slash_command(state, ["model"]) do
    show_current_model(state)
    state
  end

  defp handle_slash_command(state, ["info"]) do
    show_session_info(state)
    state
  end

  defp handle_slash_command(state, ["recent"]) do
    show_recent_conversations()
    state
  end

  defp handle_slash_command(state, ["switch", conversation_id]) do
    switch_conversation(state, conversation_id)
  end

  defp handle_slash_command(state, ["analyze", file_path]) do
    analyze_in_context(state, file_path)
  end

  defp handle_slash_command(state, ["generate" | rest]) do
    prompt = Enum.join(rest, " ")
    generate_in_context(state, prompt)
  end

  defp handle_slash_command(state, ["refactor" | rest]) do
    instruction = Enum.join(rest, " ")
    refactor_in_context(state, instruction)
  end

  defp handle_slash_command(state, _unknown) do
    IO.puts("#{@error_prefix}Unknown command. Type /help for available commands.")
    state
  end

  defp send_message(state, message) do
    IO.puts("#{@user_prefix}#{message}")
    
    # Add context if any
    message_with_context = build_message_with_context(state, message)
    
    # Show typing indicator
    typing_task = Task.async(fn -> show_typing_indicator() end)
    
    # Send message
    case send_command([
      "conversation", "send", message_with_context, 
      "--conversation", state.conversation_id
    ]) do
      {:ok, response} ->
        Task.shutdown(typing_task, :brutal_kill)
        IO.write("\r\e[K")
        
        # Extract and display assistant response
        display_assistant_response(response)
        
        # Update history
        %{state | history: state.history ++ [{:user, message}, {:assistant, response}]}
        
      {:error, reason} ->
        Task.shutdown(typing_task, :brutal_kill)
        IO.write("\r\e[K")
        IO.puts(:stderr, "#{@error_prefix}Error: #{reason}")
        state
    end
  end

  defp build_message_with_context(state, message) do
    if state.context_files == [] do
      message
    else
      context_content = Enum.map_join(state.context_files, "\n", fn file ->
        case File.read(file) do
          {:ok, content} -> "```\n# File: #{file}\n#{content}\n```"
          {:error, _} -> ""
        end
      end)
      
      """
      #{message}
      
      Context files:
      #{context_content}
      """
    end
  end

  defp show_typing_indicator do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    Enum.each(Stream.cycle(frames), fn frame ->
      IO.write("\r#{@assistant_prefix}#{frame} Thinking...")
      Process.sleep(100)
    end)
  end

  defp display_assistant_response(response) do
    # Extract the actual message content from the response
    content = extract_assistant_content(response)
    IO.puts("#{@assistant_prefix}#{content}")
  end

  defp extract_assistant_content(response) when is_binary(response) do
    # Try to extract just the assistant's message from the formatted response
    case Regex.run(~r/🤖 Assistant: (.+)/s, response) do
      [_, content] -> String.trim(content)
      _ -> response
    end
  end

  defp show_welcome(state) do
    IO.puts("""
    
    #{@system_prefix}Welcome to RubberDuck REPL!
    #{@system_prefix}Type /help for commands, /exit to quit.
    #{@system_prefix}Use \"\"\" for multi-line input, \\ for line continuation.
    #{@system_prefix}Conversation ID: #{state.conversation_id}
    #{@system_prefix}Type: #{state.conversation_type}
    
    """)
  end

  defp show_help do
    IO.puts("""
    
    #{@system_prefix}Available commands:
    
    Basic:
      /help              - Show this help message
      /exit              - Exit the REPL
      /clear             - Clear the screen
      /info              - Show session information
    
    Conversation:
      /history           - Show conversation history
      /save [filename]   - Save conversation to file
      /recent            - Show recent conversations
      /switch <id>       - Switch to another conversation
    
    Context:
      /context           - Show current context files
      /context add <file> - Add file to context
      /context clear     - Clear all context files
    
    Model:
      /model             - Show current model
      /model <model>     - Change model (e.g., /model ollama codellama)
    
    Integrated Commands:
      /analyze <file>    - Analyze code in conversation context
      /generate <prompt> - Generate code in conversation context
      /refactor <instr>  - Refactor with context
    
    Multi-line Input:
      \"\"\"                - Start/end multi-line input
      \\                  - Continue on next line
    
    """)
  end

  defp show_session_info(state) do
    IO.puts("""
    
    #{@system_prefix}Session Information:
      Conversation ID: #{state.conversation_id}
      Type: #{state.conversation_type}
      Model: #{state.model || "default"}
      Context Files: #{length(state.context_files)}
      Messages: #{length(state.history)}
      Last Save: #{format_time_ago(state.last_save_time)}
    
    """)
  end

  defp show_history(state) do
    case send_command(["conversation", "show", state.conversation_id]) do
      {:ok, history} ->
        IO.puts("\n#{@system_prefix}Conversation History:")
        IO.puts(history)
        IO.puts("")
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error loading history: #{reason}")
    end
  end

  defp show_recent_conversations do
    case send_command(["conversation", "list"]) do
      {:ok, list} ->
        IO.puts("\n#{@system_prefix}Recent Conversations:")
        IO.puts(list)
        IO.puts("\n#{@system_prefix}Use /switch <id> to switch to a conversation")
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error loading conversations: #{reason}")
    end
  end

  defp switch_conversation(state, conversation_id) do
    case send_command(["conversation", "show", conversation_id]) do
      {:ok, _} ->
        IO.puts("#{@success_prefix}Switched to conversation: #{conversation_id}")
        %{state | conversation_id: conversation_id, history: []}
      {:error, _} ->
        IO.puts(:stderr, "#{@error_prefix}Conversation not found: #{conversation_id}")
        state
    end
  end

  defp add_context_file(state, file_path) do
    expanded_path = Path.expand(file_path)
    
    if File.exists?(expanded_path) do
      IO.puts("#{@success_prefix}Added context: #{expanded_path}")
      %{state | context_files: Enum.uniq(state.context_files ++ [expanded_path])}
    else
      IO.puts(:stderr, "#{@error_prefix}File not found: #{file_path}")
      state
    end
  end

  defp show_context(state) do
    if state.context_files == [] do
      IO.puts("#{@system_prefix}No context files loaded")
    else
      IO.puts("#{@system_prefix}Context files:")
      Enum.each(state.context_files, fn file ->
        IO.puts("  - #{file}")
      end)
    end
  end

  defp change_model(state, model_spec) do
    # Parse model spec (e.g., "ollama codellama" or just "gpt-4")
    case String.split(model_spec, " ", parts: 2) do
      [provider, model] ->
        # Set model for specific provider
        case send_command(["llm", "set-model", provider, model]) do
          {:ok, _} ->
            IO.puts("#{@success_prefix}Model changed to: #{provider} #{model}")
            %{state | model: "#{provider}:#{model}"}
          {:error, reason} ->
            IO.puts(:stderr, "#{@error_prefix}Error changing model: #{reason}")
            state
        end
        
      [model] ->
        # Just model name, use default provider
        IO.puts("#{@system_prefix}Model preference noted: #{model}")
        %{state | model: model}
    end
  end

  defp show_current_model(state) do
    case send_command(["llm", "status"]) do
      {:ok, status} ->
        IO.puts("\n#{@system_prefix}LLM Status:")
        IO.puts(status)
        if state.model do
          IO.puts("#{@system_prefix}Session model preference: #{state.model}")
        end
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error getting LLM status: #{reason}")
    end
  end

  defp analyze_in_context(state, file_path) do
    message = "Please analyze the following file: #{file_path}"
    state = add_context_file(state, file_path)
    send_message(state, message)
  end

  defp generate_in_context(state, prompt) do
    message = "Please generate code for: #{prompt}"
    send_message(state, message)
  end

  defp refactor_in_context(state, instruction) do
    if state.context_files == [] do
      IO.puts("#{@error_prefix}No context files. Add files with /context add <file>")
      state
    else
      message = "Please refactor the code with this instruction: #{instruction}"
      send_message(state, message)
    end
  end

  defp save_conversation(state, filename) do
    expanded_path = Path.expand(filename)
    
    case send_command(["conversation", "show", state.conversation_id]) do
      {:ok, content} ->
        case File.write(expanded_path, content) do
          :ok ->
            IO.puts("#{@success_prefix}Conversation saved to: #{expanded_path}")
            %{state | last_save_time: System.system_time(:second)}
          {:error, reason} ->
            IO.puts(:stderr, "#{@error_prefix}Error saving file: #{reason}")
            state
        end
      {:error, reason} ->
        IO.puts(:stderr, "#{@error_prefix}Error getting conversation: #{reason}")
        state
    end
  end

  defp maybe_auto_save(state) do
    current_time = System.system_time(:second)
    # Auto-save every 5 minutes
    if current_time - state.last_save_time > 300 do
      filename = ".rubber_duck_repl_autosave_#{state.conversation_id}.md"
      save_conversation(state, filename)
    else
      state
    end
  end

  defp handle_exit(state) do
    IO.puts("\n#{@system_prefix}Saving session...")
    filename = ".rubber_duck_repl_last_#{state.conversation_id}.md"
    save_conversation(state, filename)
    IO.puts("#{@system_prefix}Goodbye!")
    System.halt(0)
  end

  defp clear_screen do
    IO.write("\e[2J\e[H")
  end

  defp send_command(args) do
    config = build_config()
    
    case RubberDuck.CLIClient.UnifiedIntegration.execute_command(args, config) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_config do
    %{
      user_id: Auth.get_user_id(),
      session_id: "cli_repl_#{System.system_time(:millisecond)}",
      permissions: [:read, :write, :execute],
      format: :text,
      server_url: Auth.get_server_url(),
      metadata: %{
        cli_version: "0.1.0",
        interactive: true,
        repl: true
      }
    }
  end

  defp extract_first_conversation_id(output) do
    case Regex.run(~r/([a-f0-9-]+) - /, output) do
      [_, id] -> {:ok, id}
      _ -> {:error, "No conversations found"}
    end
  end

  defp format_timestamp do
    {{year, month, day}, {hour, minute, _}} = :calendar.local_time()
    "#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(minute)}"
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp format_time_ago(timestamp) do
    diff = System.system_time(:second) - timestamp
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end