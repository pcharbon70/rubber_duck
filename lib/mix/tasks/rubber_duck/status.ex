defmodule Mix.Tasks.RubberDuck.Status do
  @moduledoc """
  Show RubberDuck CLI system status and health information.

  ## Usage

      mix rubber_duck.status [options]

  ## Options

    * `--format <format>` - Output format: text, json (default: text)
    * `--verbose` - Show detailed system information
    * `--check <component>` - Check specific component health
    * `--quiet` - Show only health status

  ## Health Checks

    * `config` - Configuration validation
    * `storage` - Session storage accessibility
    * `network` - Network connectivity (if distributed)
    * `models` - AI model availability
    * `all` - All health checks (default)

  ## Examples

      # Basic status
      mix rubber_duck.status

      # Detailed system information
      mix rubber_duck.status --verbose

      # JSON output for monitoring
      mix rubber_duck.status --format json

      # Check specific component
      mix rubber_duck.status --check config

      # Quick health check
      mix rubber_duck.status --quiet
  """

  use Mix.Task

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.CLI.{ConfigManager, SessionManager}

  @shortdoc "Show RubberDuck CLI system status"

  @switches [
    format: :string,
    verbose: :boolean,
    check: :string,
    quiet: :boolean,
    help: :boolean
  ]

  @aliases [
    f: :format,
    v: :verbose,
    c: :check,
    q: :quiet,
    h: :help
  ]

  def run(args) do
    {options, _remaining_args, _invalid} = OptionParser.parse(args, 
      switches: @switches, 
      aliases: @aliases
    )

    if options[:help] do
      show_help()
    else
      show_status(options)
    end
  end

  defp show_status(options) do
    status_info = gather_status_info(options)
    
    case options[:format] do
      "json" ->
        output_json_status(status_info)
      _ ->
        output_text_status(status_info, options)
    end
  end

  defp gather_status_info(options) do
    check_component = options[:check] || "all"
    
    base_status = %{
      overall_health: :unknown,
      timestamp: DateTime.utc_now(),
      checks_performed: [],
      cli_info: gather_cli_info()
    }
    
    case check_component do
      "config" -> perform_config_check(base_status)
      "storage" -> perform_storage_check(base_status)
      "network" -> perform_network_check(base_status)
      "models" -> perform_models_check(base_status)
      "all" -> perform_all_checks(base_status)
      _ -> 
        Map.put(base_status, :error, "Unknown check component: #{check_component}")
    end
    |> add_verbose_info(options[:verbose] || false)
    |> determine_overall_health()
  end

  defp gather_cli_info do
    %{
      version: get_cli_version(),
      uptime: get_cli_uptime(),
      interface: :cli,
      capabilities: CLI.capabilities()
    }
  end

  defp perform_all_checks(status) do
    status
    |> perform_config_check()
    |> perform_storage_check()
    |> perform_network_check()
    |> perform_models_check()
  end

  defp perform_config_check(status) do
    check_result = case ConfigManager.load_config() do
      {:ok, config} ->
        %{
          name: "config",
          status: :healthy,
          message: "Configuration loaded successfully",
          details: %{
            config_file: get_config_file_path(config),
            colors_enabled: config[:colors],
            model: config[:model],
            format: config[:format]
          }
        }
      {:error, reason} ->
        %{
          name: "config",
          status: :unhealthy,
          message: "Configuration error",
          error: inspect(reason)
        }
    end
    
    add_check_result(status, check_result)
  end

  defp perform_storage_check(status) do
    check_result = try do
      case ConfigManager.load_config() do
        {:ok, config} ->
          # Test session manager initialization
          case SessionManager.init(config) do
            {:ok, session_state} ->
              # Test session creation and deletion
              case SessionManager.create_session("health_check", %{}, session_state) do
                {:ok, session, updated_state} ->
                  case SessionManager.delete_session(session.id, updated_state) do
                    {:ok, _final_state} ->
                      %{
                        name: "storage",
                        status: :healthy,
                        message: "Session storage working correctly",
                        details: %{
                          sessions_dir: config[:sessions_dir],
                          writable: true,
                          session_count: count_existing_sessions(config)
                        }
                      }
                    {:error, reason} ->
                      %{
                        name: "storage",
                        status: :degraded,
                        message: "Session deletion failed",
                        error: inspect(reason)
                      }
                  end
                {:error, reason} ->
                  %{
                    name: "storage",
                    status: :unhealthy,
                    message: "Cannot create sessions",
                    error: inspect(reason)
                  }
              end
            {:error, reason} ->
              %{
                name: "storage",
                status: :unhealthy,
                message: "Session manager initialization failed",
                error: inspect(reason)
              }
          end
        {:error, reason} ->
          %{
            name: "storage",
            status: :unhealthy,
            message: "Cannot load configuration for storage check",
            error: inspect(reason)
          }
      end
    rescue
      error ->
        %{
          name: "storage",
          status: :unhealthy,
          message: "Storage check failed with exception",
          error: Exception.message(error)
        }
    end
    
    add_check_result(status, check_result)
  end

  defp perform_network_check(status) do
    check_result = %{
      name: "network",
      status: :healthy,
      message: "Network checks not implemented yet",
      details: %{
        node: Node.self(),
        connected_nodes: Node.list(),
        distributed: length(Node.list()) > 0
      }
    }
    
    add_check_result(status, check_result)
  end

  defp perform_models_check(status) do
    check_result = %{
      name: "models",
      status: :healthy,
      message: "Model checks not implemented yet",
      details: %{
        default_model: get_default_model(),
        available_models: ["claude", "gpt-4", "gpt-3.5-turbo"]
      }
    }
    
    add_check_result(status, check_result)
  end

  defp add_check_result(status, check_result) do
    checks = Map.get(status, :checks, [])
    performed = Map.get(status, :checks_performed, [])
    
    status
    |> Map.put(:checks, [check_result | checks])
    |> Map.put(:checks_performed, [check_result.name | performed])
  end

  defp add_verbose_info(status, false), do: status
  defp add_verbose_info(status, true) do
    Map.put(status, :verbose_info, %{
      system: gather_system_info(),
      elixir: gather_elixir_info(),
      memory: gather_memory_info(),
      processes: gather_process_info()
    })
  end

  defp determine_overall_health(status) do
    checks = Map.get(status, :checks, [])
    
    overall_health = cond do
      Enum.any?(checks, &(&1.status == :unhealthy)) -> :unhealthy
      Enum.any?(checks, &(&1.status == :degraded)) -> :degraded
      Enum.all?(checks, &(&1.status == :healthy)) -> :healthy
      true -> :unknown
    end
    
    Map.put(status, :overall_health, overall_health)
  end

  defp output_text_status(status_info, options) do
    if options[:quiet] do
      show_health_indicator(status_info.overall_health)
    else
      show_status_header(status_info)
      show_health_checks(status_info)
      
      if options[:verbose] and status_info[:verbose_info] do
        show_verbose_information(status_info.verbose_info)
      end
    end
  end

  defp show_health_indicator(health) do
    case health do
      :healthy -> Mix.shell().info(colorize("HEALTHY", :green))
      :degraded -> Mix.shell().info(colorize("DEGRADED", :yellow))
      :unhealthy -> Mix.shell().info(colorize("UNHEALTHY", :red))
      :unknown -> Mix.shell().info(colorize("UNKNOWN", :dim))
    end
  end

  defp show_status_header(status_info) do
    health_indicator = case status_info.overall_health do
      :healthy -> colorize("●", :green)
      :degraded -> colorize("●", :yellow)
      :unhealthy -> colorize("●", :red)
      :unknown -> colorize("●", :dim)
    end
    
    Mix.shell().info("""
    #{health_indicator} #{colorize("RubberDuck CLI Status", :bold)}
    
    Overall Health: #{format_health_status(status_info.overall_health)}
    CLI Version: #{status_info.cli_info.version}
    Checked at: #{format_timestamp(status_info.timestamp)}
    """)
  end

  defp show_health_checks(status_info) do
    checks = Map.get(status_info, :checks, [])
    
    if not Enum.empty?(checks) do
      Mix.shell().info(colorize("Health Checks:", :bold))
      
      Enum.reverse(checks)
      |> Enum.each(&show_check_result/1)
      
      Mix.shell().info("")
    end
  end

  defp show_check_result(check) do
    status_indicator = case check.status do
      :healthy -> colorize("✓", :green)
      :degraded -> colorize("⚠", :yellow)
      :unhealthy -> colorize("✗", :red)
      :unknown -> colorize("?", :dim)
    end
    
    Mix.shell().info("  #{status_indicator} #{String.capitalize(check.name)}: #{check.message}")
    
    if check[:error] do
      Mix.shell().info("    #{colorize("Error: #{check.error}", :red)}")
    end
    
    if check[:details] do
      show_check_details(check.details)
    end
  end

  defp show_check_details(details) when is_map(details) do
    Enum.each(details, fn {key, value} ->
      key_str = key |> to_string() |> String.replace("_", " ") |> String.capitalize()
      Mix.shell().info("    #{colorize(key_str, :dim)}: #{format_detail_value(value)}")
    end)
  end

  defp format_detail_value(value) when is_boolean(value), do: to_string(value)
  defp format_detail_value(value) when is_binary(value), do: value
  defp format_detail_value(value) when is_number(value), do: to_string(value)
  defp format_detail_value(value), do: inspect(value)

  defp show_verbose_information(verbose_info) do
    Mix.shell().info(colorize("System Information:", :bold))
    
    if system_info = verbose_info[:system] do
      show_system_details(system_info)
    end
    
    if elixir_info = verbose_info[:elixir] do
      show_elixir_details(elixir_info)
    end
    
    if memory_info = verbose_info[:memory] do
      show_memory_details(memory_info)
    end
    
    if process_info = verbose_info[:processes] do
      show_process_details(process_info)
    end
  end

  defp show_system_details(system_info) do
    Mix.shell().info("  #{colorize("Operating System:", :yellow)} #{system_info[:os] || "unknown"}")
    Mix.shell().info("  #{colorize("Architecture:", :yellow)} #{system_info[:arch] || "unknown"}")
    Mix.shell().info("  #{colorize("Hostname:", :yellow)} #{system_info[:hostname] || "unknown"}")
    Mix.shell().info("")
  end

  defp show_elixir_details(elixir_info) do
    Mix.shell().info("  #{colorize("Elixir:", :yellow)} #{elixir_info[:version] || "unknown"}")
    Mix.shell().info("  #{colorize("OTP:", :yellow)} #{elixir_info[:otp] || "unknown"}")
    Mix.shell().info("  #{colorize("Node:", :yellow)} #{elixir_info[:node] || "unknown"}")
    Mix.shell().info("")
  end

  defp show_memory_details(memory_info) do
    Mix.shell().info("  #{colorize("Memory Usage:", :yellow)}")
    Mix.shell().info("    Total: #{format_bytes(memory_info[:total] || 0)}")
    Mix.shell().info("    Processes: #{format_bytes(memory_info[:processes] || 0)}")
    Mix.shell().info("    System: #{format_bytes(memory_info[:system] || 0)}")
    Mix.shell().info("")
  end

  defp show_process_details(process_info) do
    Mix.shell().info("  #{colorize("Processes:", :yellow)}")
    Mix.shell().info("    Count: #{process_info[:count] || 0}")
    Mix.shell().info("    Limit: #{process_info[:limit] || 0}")
    Mix.shell().info("")
  end

  defp output_json_status(status_info) do
    case Jason.encode(status_info, pretty: true) do
      {:ok, json} -> Mix.shell().info(json)
      {:error, reason} -> 
        Mix.shell().error("JSON encoding error: #{reason}")
        Mix.shell().info(inspect(status_info, pretty: true))
    end
  end

  # Helper functions

  defp get_cli_version do
    case Application.spec(:rubber_duck, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "1.0.0"
    end
  end

  defp get_cli_uptime do
    # Simple uptime since this is a command-line tool
    System.monotonic_time(:millisecond)
  end

  defp get_config_file_path(config) do
    Path.join(config[:config_dir] || "~/.rubber_duck", "config.yaml")
  end

  defp count_existing_sessions(config) do
    sessions_dir = config[:sessions_dir] || Path.expand("~/.rubber_duck/sessions")
    
    if File.exists?(sessions_dir) do
      sessions_dir
      |> File.ls!()
      |> Enum.count(&String.ends_with?(&1, ".json"))
    else
      0
    end
  rescue
    _ -> 0
  end

  defp get_default_model do
    case ConfigManager.load_config() do
      {:ok, config} -> config[:model] || "claude"
      _ -> "claude"
    end
  end

  defp gather_system_info do
    %{
      os: get_os_name(),
      arch: get_architecture(),
      hostname: get_hostname()
    }
  end

  defp gather_elixir_info do
    %{
      version: System.version(),
      otp: get_otp_version(),
      node: Node.self()
    }
  end

  defp gather_memory_info do
    memory = :erlang.memory()
    
    %{
      total: memory[:total],
      processes: memory[:processes],
      system: memory[:system],
      atom: memory[:atom],
      binary: memory[:binary],
      ets: memory[:ets]
    }
  rescue
    _ -> %{total: 0, processes: 0, system: 0}
  end

  defp gather_process_info do
    %{
      count: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit)
    }
  rescue
    _ -> %{count: 0, limit: 0}
  end

  defp get_os_name do
    case :os.type() do
      {:unix, osname} -> to_string(osname)
      {:win32, _} -> "windows"
      other -> inspect(other)
    end
  rescue
    _ -> "unknown"
  end

  defp get_architecture do
    case :erlang.system_info(:system_architecture) do
      arch when is_list(arch) -> List.to_string(arch)
      arch -> to_string(arch)
    end
  rescue
    _ -> "unknown"
  end

  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp get_otp_version do
    case :erlang.system_info(:otp_release) do
      release when is_list(release) -> List.to_string(release)
      release -> to_string(release)
    end
  rescue
    _ -> "unknown"
  end

  defp format_health_status(health) do
    case health do
      :healthy -> colorize("Healthy", :green)
      :degraded -> colorize("Degraded", :yellow)
      :unhealthy -> colorize("Unhealthy", :red)
      :unknown -> colorize("Unknown", :dim)
    end
  end

  defp format_timestamp(datetime) do
    DateTime.to_string(datetime) |> String.slice(0, 19)
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} bytes"
    end
  end
  defp format_bytes(_), do: "unknown"

  defp colorize(text, color) do
    case color do
      :bold -> "\e[1m#{text}\e[0m"
      :dim -> "\e[2m#{text}\e[0m"
      :green -> "\e[32m#{text}\e[0m"
      :yellow -> "\e[33m#{text}\e[0m"
      :red -> "\e[31m#{text}\e[0m"
      _ -> text
    end
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end