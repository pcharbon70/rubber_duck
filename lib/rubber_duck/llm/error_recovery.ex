defmodule RubberDuck.LLM.ErrorRecovery do
  @moduledoc """
  Error recovery strategies for LLM failures.
  
  This module provides fallback mechanisms when LLM requests fail,
  including:
  - Provider failover
  - Model downgrade
  - Cached response retrieval
  - Graceful degradation
  """
  
  require Logger
  
  alias RubberDuck.LLM.{ErrorHandler, ServiceV2}
  
  @doc """
  Attempts to recover from an LLM error using various strategies.
  """
  @spec attempt_recovery(ErrorHandler.formatted_error(), keyword()) :: 
    {:ok, map()} | {:error, ErrorHandler.formatted_error()}
  def attempt_recovery({_error_type, _context} = error, original_opts) do
    strategies = [
      &try_fallback_provider/2,
      &try_alternative_model/2,
      &try_cached_response/2,
      &try_simplified_request/2
    ]
    
    Enum.reduce_while(strategies, {:error, error}, fn strategy, {:error, _} = acc ->
      case strategy.(error, original_opts) do
        {:ok, _result} = success ->
          {:halt, success}
          
        {:error, _reason} ->
          {:cont, acc}
      end
    end)
  end
  
  @doc """
  Provides a graceful degradation response when all recovery attempts fail.
  """
  @spec graceful_degradation(ErrorHandler.formatted_error(), keyword()) :: map()
  def graceful_degradation({error_type, context}, opts) do
    %{
      choices: [
        %{
          index: 0,
          message: %{
            role: "assistant",
            content: build_degradation_message(error_type, context, opts)
          },
          finish_reason: "error_recovery"
        }
      ],
      usage: nil,
      model: "fallback",
      provider: :system,
      metadata: %{
        error_type: error_type,
        recovery_attempted: true,
        degraded: true
      }
    }
  end
  
  # Private recovery strategies
  
  defp try_fallback_provider({_error_type, _context} = _error, opts) do
    current_provider = Keyword.get(opts, :provider)
    
    case get_fallback_provider(current_provider) do
      nil ->
        {:error, :no_fallback_provider}
        
      fallback_provider ->
        Logger.info("Attempting recovery with fallback provider: #{fallback_provider}")
        
        # Try with fallback provider
        fallback_opts = 
          opts
          |> Keyword.put(:provider, fallback_provider)
          |> Keyword.put(:model, get_default_model(fallback_provider))
          |> Keyword.put(:max_retries, 1)  # Limit retries for fallback
          
        case ServiceV2.completion(fallback_opts) do
          {:ok, response} ->
            Logger.info("Successfully recovered using fallback provider: #{fallback_provider}")
            
            # Add metadata about fallback
            enhanced_response = Map.put(response, :metadata, 
              Map.merge(response[:metadata] || %{}, %{
                fallback_used: true,
                original_provider: current_provider,
                fallback_provider: fallback_provider
              })
            )
            
            {:ok, enhanced_response}
            
          {:error, _reason} ->
            {:error, :fallback_provider_failed}
        end
    end
  end
  
  defp try_alternative_model({_error_type, _context}, opts) do
    current_model = Keyword.get(opts, :model)
    provider = Keyword.get(opts, :provider)
    
    case get_alternative_model(provider, current_model) do
      nil ->
        {:error, :no_alternative_model}
        
      alt_model ->
        Logger.info("Attempting recovery with alternative model: #{alt_model}")
        
        # Try with alternative model
        alt_opts = 
          opts
          |> Keyword.put(:model, alt_model)
          |> Keyword.put(:max_retries, 1)
          
        case ServiceV2.completion(alt_opts) do
          {:ok, response} ->
            Logger.info("Successfully recovered using alternative model: #{alt_model}")
            
            # Add metadata
            enhanced_response = Map.put(response, :metadata,
              Map.merge(response[:metadata] || %{}, %{
                alternative_model_used: true,
                original_model: current_model,
                alternative_model: alt_model
              })
            )
            
            {:ok, enhanced_response}
            
          {:error, _reason} ->
            {:error, :alternative_model_failed}
        end
    end
  end
  
  defp try_cached_response({_error_type, _context}, _opts) do
    # Check if we have a recent similar request in cache
    # This would integrate with a caching layer
    # For now, return not found
    {:error, :no_cached_response}
  end
  
  defp try_simplified_request({error_type, _context}, opts) when error_type == :context_too_large do
    messages = Keyword.get(opts, :messages, [])
    
    if length(messages) > 2 do
      # Keep only the most recent messages
      simplified_messages = Enum.take(messages, -2)
      
      Logger.info("Attempting recovery with simplified context (#{length(messages)} -> #{length(simplified_messages)} messages)")
      
      simplified_opts = 
        opts
        |> Keyword.put(:messages, simplified_messages)
        |> Keyword.put(:max_retries, 1)
        
      case ServiceV2.completion(simplified_opts) do
        {:ok, response} ->
          Logger.info("Successfully recovered using simplified request")
          
          # Add metadata
          enhanced_response = Map.put(response, :metadata,
            Map.merge(response[:metadata] || %{}, %{
              context_simplified: true,
              original_message_count: length(messages),
              simplified_message_count: length(simplified_messages)
            })
          )
          
          {:ok, enhanced_response}
          
        {:error, _reason} ->
          {:error, :simplified_request_failed}
      end
    else
      {:error, :cannot_simplify_further}
    end
  end
  
  defp try_simplified_request(_, _), do: {:error, :not_applicable}
  
  # Helper functions
  
  defp get_fallback_provider(current_provider) do
    # Define fallback chain
    fallback_map = %{
      openai: :anthropic,
      anthropic: :openai,
      ollama: :openai,
      tgi: :ollama
    }
    
    Map.get(fallback_map, current_provider)
  end
  
  defp get_default_model(provider) do
    case provider do
      :openai -> "gpt-3.5-turbo"
      :anthropic -> "claude-3-haiku"
      :ollama -> "llama2"
      :tgi -> "mistral-7b"
      _ -> nil
    end
  end
  
  defp get_alternative_model(provider, current_model) do
    # Define model alternatives
    alternatives = %{
      openai: %{
        "gpt-4" => "gpt-3.5-turbo",
        "gpt-4-turbo" => "gpt-3.5-turbo",
        "gpt-3.5-turbo" => nil
      },
      anthropic: %{
        "claude-3-opus" => "claude-3-sonnet",
        "claude-3-sonnet" => "claude-3-haiku",
        "claude-3-haiku" => nil
      },
      ollama: %{
        "codellama" => "llama2",
        "llama2" => "mistral",
        "mistral" => nil
      }
    }
    
    get_in(alternatives, [provider, current_model])
  end
  
  defp build_degradation_message(error_type, _context, _opts) do
    base_message = "I apologize, but I'm currently unable to process your request"
    
    detail = case error_type do
      :rate_limit_exceeded ->
        ". The service is experiencing high demand. Please try again in a few moments."
        
      :service_unavailable ->
        ". The AI service is temporarily unavailable. Please try again later."
        
      :authentication_failed ->
        ". There's an issue with the service configuration. Please contact support."
        
      :context_too_large ->
        ". The conversation has become too long. Please start a new conversation."
        
      _ ->
        ". Please try again or contact support if the issue persists."
    end
    
    suggestions = case error_type do
      :context_too_large ->
        "\n\nYou can:\n- Start a new conversation\n- Summarize your previous questions\n- Focus on a specific topic"
        
      :rate_limit_exceeded ->
        "\n\nYou can:\n- Wait a few moments before trying again\n- Reduce the frequency of requests\n- Contact support for higher limits"
        
      _ ->
        ""
    end
    
    base_message <> detail <> suggestions
  end
end