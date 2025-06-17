defmodule Mix.Tasks.RubberDuck.Version do
  @moduledoc """
  Show RubberDuck CLI version and build information.

  ## Usage

      mix rubber_duck.version [options]

  ## Options

    * `--format <format>` - Output format: text, json (default: text)
    * `--verbose` - Show detailed build and system information
    * `--quiet` - Show version number only

  ## Examples

      # Basic version
      mix rubber_duck.version

      # Detailed information
      mix rubber_duck.version --verbose

      # JSON output
      mix rubber_duck.version --format json

      # Just the version number
      mix rubber_duck.version --quiet
  """

  use Mix.Task

  @shortdoc "Show RubberDuck CLI version information"

  @switches [
    format: :string,
    verbose: :boolean,
    quiet: :boolean,
    help: :boolean
  ]

  @aliases [
    f: :format,
    v: :verbose,
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
      show_version(options)
    end
  end

  defp show_version(options) do
    version_info = gather_version_info(options)
    
    case options[:format] do
      "json" ->
        output_json_version(version_info)
      _ ->
        output_text_version(version_info, options)
    end
  end

  defp gather_version_info(options) do
    # Get application version
    app_version = get_app_version()
    
    base_info = %{
      version: app_version,
      application: "RubberDuck CLI",
      description: "AI-powered coding assistant for the command line"
    }
    
    if options[:verbose] do
      Map.merge(base_info, gather_detailed_info())
    else
      base_info
    end
  end

  defp get_app_version do
    case Application.spec(:rubber_duck, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "1.0.0"  # Fallback version
    end
  end

  defp gather_detailed_info do
    %{
      build_info: gather_build_info(),
      system_info: gather_system_info(),
      elixir_info: gather_elixir_info(),
      dependencies: gather_dependency_info()
    }
  end

  defp gather_build_info do
    %{
      compiled_at: get_compile_time(),
      git_commit: get_git_commit(),
      git_branch: get_git_branch(),
      build_env: get_build_env()
    }
  end

  defp gather_system_info do
    %{
      os: get_os_info(),
      architecture: get_architecture(),
      hostname: get_hostname(),
      user: get_current_user()
    }
  end

  defp gather_elixir_info do
    %{
      elixir_version: System.version(),
      otp_version: get_otp_version(),
      erts_version: get_erts_version(),
      node: Node.self()
    }
  end

  defp gather_dependency_info do
    case Mix.Project.deps_paths() do
      deps when is_map(deps) ->
        deps
        |> Map.keys()
        |> Enum.map(&get_dependency_version/1)
        |> Enum.into(%{})
      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp output_text_version(version_info, options) do
    if options[:quiet] do
      Mix.shell().info(version_info.version)
    else
      show_basic_version_info(version_info)
      
      if options[:verbose] do
        show_detailed_version_info(version_info)
      end
    end
  end

  defp show_basic_version_info(version_info) do
    Mix.shell().info("""
    #{colorize("RubberDuck CLI", :cyan)} #{colorize("v#{version_info.version}", :green)}
    #{colorize(version_info.description, :dim)}
    """)
  end

  defp show_detailed_version_info(version_info) do
    if build_info = version_info[:build_info] do
      show_build_information(build_info)
    end
    
    if system_info = version_info[:system_info] do
      show_system_information(system_info)
    end
    
    if elixir_info = version_info[:elixir_info] do
      show_elixir_information(elixir_info)
    end
    
    if dependencies = version_info[:dependencies] do
      show_dependency_information(dependencies)
    end
  end

  defp show_build_information(build_info) do
    Mix.shell().info(colorize("Build Information:", :yellow))
    
    if build_info[:compiled_at] do
      Mix.shell().info("  Compiled: #{build_info.compiled_at}")
    end
    
    if build_info[:git_commit] do
      commit = String.slice(build_info.git_commit, 0, 8)
      Mix.shell().info("  Git commit: #{commit}")
    end
    
    if build_info[:git_branch] do
      Mix.shell().info("  Git branch: #{build_info.git_branch}")
    end
    
    if build_info[:build_env] do
      Mix.shell().info("  Environment: #{build_info.build_env}")
    end
    
    Mix.shell().info("")
  end

  defp show_system_information(system_info) do
    Mix.shell().info(colorize("System Information:", :yellow))
    
    if system_info[:os] do
      Mix.shell().info("  Operating System: #{system_info.os}")
    end
    
    if system_info[:architecture] do
      Mix.shell().info("  Architecture: #{system_info.architecture}")
    end
    
    if system_info[:hostname] do
      Mix.shell().info("  Hostname: #{system_info.hostname}")
    end
    
    if system_info[:user] do
      Mix.shell().info("  User: #{system_info.user}")
    end
    
    Mix.shell().info("")
  end

  defp show_elixir_information(elixir_info) do
    Mix.shell().info(colorize("Elixir Information:", :yellow))
    
    Mix.shell().info("  Elixir: #{elixir_info.elixir_version}")
    
    if elixir_info[:otp_version] do
      Mix.shell().info("  OTP: #{elixir_info.otp_version}")
    end
    
    if elixir_info[:erts_version] do
      Mix.shell().info("  ERTS: #{elixir_info.erts_version}")
    end
    
    Mix.shell().info("  Node: #{elixir_info.node}")
    Mix.shell().info("")
  end

  defp show_dependency_information(dependencies) do
    if not Enum.empty?(dependencies) do
      Mix.shell().info(colorize("Key Dependencies:", :yellow))
      
      # Show only important dependencies
      important_deps = [:phoenix, :ecto, :jason, :hackney, :httpoison, :tesla]
      
      dependencies
      |> Enum.filter(fn {dep, _version} -> dep in important_deps end)
      |> Enum.each(fn {dep, version} ->
        Mix.shell().info("  #{dep}: #{version}")
      end)
      
      Mix.shell().info("")
    end
  end

  defp output_json_version(version_info) do
    case Jason.encode(version_info, pretty: true) do
      {:ok, json} -> Mix.shell().info(json)
      {:error, reason} -> 
        Mix.shell().error("JSON encoding error: #{reason}")
        Mix.shell().info(inspect(version_info, pretty: true))
    end
  end

  # Helper functions to gather system information

  defp get_compile_time do
    case :application.get_key(:rubber_duck, :modules) do
      {:ok, modules} when is_list(modules) ->
        case List.first(modules) do
          nil -> "unknown"
          module ->
            case :code.get_object_code(module) do
              {^module, beam, _filename} ->
                case :beam_lib.chunks(beam, [:compile_info]) do
                  {:ok, {^module, [{:compile_info, info}]}} ->
                    case Keyword.get(info, :time) do
                      {{year, month, day}, {hour, minute, second}} ->
                        "#{year}-#{:io_lib.format(~c"~2..0w", [month])}-#{:io_lib.format(~c"~2..0w", [day])} " <>
                        "#{:io_lib.format(~c"~2..0w", [hour])}:#{:io_lib.format(~c"~2..0w", [minute])}:#{:io_lib.format(~c"~2..0w", [second])}"
                      _ -> "unknown"
                    end
                  _ -> "unknown"
                end
              _ -> "unknown"
            end
        end
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp get_git_commit do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {commit, 0} -> String.trim(commit)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp get_git_branch do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true) do
      {branch, 0} -> String.trim(branch)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp get_build_env do
    Mix.env() |> to_string()
  end

  defp get_os_info do
    case :os.type() do
      {:unix, osname} -> 
        osname_str = osname |> to_string()
        case System.cmd("uname", ["-r"], stderr_to_stdout: true) do
          {release, 0} -> "#{osname_str} #{String.trim(release)}"
          _ -> osname_str
        end
      {:win32, _} -> "Windows"
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

  defp get_current_user do
    System.get_env("USER") || System.get_env("USERNAME") || "unknown"
  end

  defp get_otp_version do
    case :erlang.system_info(:otp_release) do
      release when is_list(release) -> List.to_string(release)
      release -> to_string(release)
    end
  rescue
    _ -> "unknown"
  end

  defp get_erts_version do
    case :erlang.system_info(:version) do
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  rescue
    _ -> "unknown"
  end

  defp get_dependency_version(dep_name) do
    try do
      case Application.spec(dep_name, :vsn) do
        vsn when is_list(vsn) -> {dep_name, List.to_string(vsn)}
        _ -> {dep_name, "unknown"}
      end
    rescue
      _ -> {dep_name, "unknown"}
    end
  end

  defp colorize(text, color) do
    case color do
      :cyan -> "\e[36m#{text}\e[0m"
      :green -> "\e[32m#{text}\e[0m"
      :yellow -> "\e[33m#{text}\e[0m"
      :dim -> "\e[2m#{text}\e[0m"
      _ -> text
    end
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end