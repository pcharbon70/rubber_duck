defmodule RubberDuck.CLIClient.Commands.LLM do
  @moduledoc """
  LLM management command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    case args do
      %{subcommand: {subcommand, subargs}} ->
        handle_subcommand(subcommand, subargs, opts)
        
      _ ->
        handle_subcommand(:status, %{}, opts)
    end
  end

  defp handle_subcommand(:status, _args, _opts) do
    params = %{"subcommand" => "status"}
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:connect, args, _opts) do
    params = %{
      "subcommand" => "connect",
      "provider" => args[:provider]
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:disconnect, args, _opts) do
    params = %{
      "subcommand" => "disconnect", 
      "provider" => args[:provider]
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:enable, args, _opts) do
    params = %{
      "subcommand" => "enable",
      "provider" => args.provider
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:disable, args, _opts) do
    params = %{
      "subcommand" => "disable",
      "provider" => args.provider
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end