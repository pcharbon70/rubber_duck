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
        {:ok, format_status_result(result)}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:connect, args, _opts) do
    provider = 
      case args do
        %{args: %{provider: p}} -> p
        _ -> nil
      end
      
    params = %{
      "subcommand" => "connect",
      "provider" => provider
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        message = format_connect_result(result, provider)
        {:ok, message}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:disconnect, args, _opts) do
    provider = 
      case args do
        %{args: %{provider: p}} -> p
        _ -> nil
      end
      
    params = %{
      "subcommand" => "disconnect", 
      "provider" => provider
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:enable, args, _opts) do
    provider = 
      case args do
        %{args: %{provider: p}} -> p
        _ -> nil
      end
      
    params = %{
      "subcommand" => "enable",
      "provider" => provider
    }
    
    case Client.send_command("llm", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp handle_subcommand(:disable, args, _opts) do
    provider = 
      case args do
        %{args: %{provider: p}} -> p
        _ -> nil
      end
      
    params = %{
      "subcommand" => "disable",
      "provider" => provider
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
  
  defp format_connect_result(%{"message" => message}, _provider) do
    message
  end
  
  defp format_connect_result(%{"error" => error}, provider) do
    "Failed to connect to #{provider}: #{error}"
  end
  
  defp format_connect_result(_result, provider) do
    "Connected to #{provider}"
  end
  
  defp format_status_result(%{"providers" => providers}) when is_list(providers) do
    """
    LLM Provider Status:
    
    #{format_providers(providers)}
    """
  end
  
  defp format_status_result(result) do
    inspect(result)
  end
  
  defp format_providers(providers) do
    providers
    |> Enum.map(&format_provider/1)
    |> Enum.join("\n")
  end
  
  defp format_provider(%{"name" => name, "status" => status, "enabled" => enabled}) do
    enabled_text = if enabled, do: "Enabled", else: "Disabled"
    "• #{name}: #{status} (#{enabled_text})"
  end
  
  defp format_provider(provider) do
    "• #{inspect(provider)}"
  end
end