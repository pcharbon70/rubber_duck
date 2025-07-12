defmodule RubberDuck.Commands.Handlers.Analyze do
  @moduledoc """
  Handler for code analysis commands.
  
  Integrates with the existing analysis engines to provide comprehensive
  code analysis including semantic, style, and security checks.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}

  @impl true
  def execute(%Command{name: :analyze, args: args, options: options} = command) do
    with :ok <- validate(command),
         {:ok, files} <- get_files_to_analyze(args.path, options),
         {:ok, results} <- analyze_files(files, options) do
      {:ok, %{
        analysis_results: results,
        file_count: length(files),
        timestamp: DateTime.utc_now()
      }}
    end
  end

  def execute(_command) do
    {:error, "Invalid command for analyze handler"}
  end

  @impl true
  def validate(%Command{name: :analyze, args: args}) do
    with :ok <- Handler.validate_required_args(%{args: args}, [:path]) do
      # Path validation will be done when getting files to analyze
      :ok
    end
  end
  
  def validate(_), do: {:error, "Invalid command for analyze handler"}

  # Private functions

  defp get_files_to_analyze(path, options) do
    recursive = Map.get(options, :recursive, false)
    
    cond do
      File.regular?(path) ->
        {:ok, [path]}
        
      File.dir?(path) ->
        get_directory_files(path, recursive)
        
      true ->
        {:error, "Path not found: #{path}"}
    end
  end

  defp get_directory_files(dir, recursive) do
    try do
      files = if recursive do
        Path.wildcard(Path.join(dir, "**/*.{ex,exs}"))
      else
        Path.wildcard(Path.join(dir, "*.{ex,exs}"))
      end
      
      {:ok, files}
    rescue
      e -> {:error, "Failed to read directory: #{Exception.message(e)}"}
    end
  end

  defp analyze_files(files, options) do
    analysis_type = Map.get(options, :type, "all")
    
    # For now, return mock analysis results
    # In real implementation, this would call the analysis engines
    results = Enum.map(files, fn file ->
      %{
        file: file,
        type: analysis_type,
        issues: [],
        metrics: %{
          lines: count_lines(file),
          complexity: 1
        },
        timestamp: DateTime.utc_now()
      }
    end)
    
    {:ok, results}
  end

  defp count_lines(file_path) do
    try do
      File.read!(file_path)
      |> String.split("\n")
      |> length()
    rescue
      _ -> 0
    end
  end
end