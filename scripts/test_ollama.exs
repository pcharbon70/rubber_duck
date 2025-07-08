#!/usr/bin/env elixir

# Test script for Ollama provider
# Run with: elixir scripts/test_ollama.exs

# Load the application
Mix.install([
  {:req, "~> 0.4.0"},
  {:jason, "~> 1.4"}
])

# Test Ollama provider functionality
defmodule OllamaTest do
  def test_connection do
    IO.puts("Testing Ollama connection...")
    
    url = "http://localhost:11434/api/tags"
    
    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("✓ Ollama is running!")
        IO.puts("Available models:")
        
        if body["models"] do
          Enum.each(body["models"], fn model ->
            IO.puts("  - #{model["name"]}")
          end)
        else
          IO.puts("  (no models found)")
        end
        
      {:ok, %{status: status}} ->
        IO.puts("✗ Ollama returned status #{status}")
        
      {:error, reason} ->
        IO.puts("✗ Connection failed: #{inspect(reason)}")
        IO.puts("\nMake sure Ollama is running with: ollama serve")
    end
  end
  
  def test_chat_request do
    IO.puts("\nTesting chat request...")
    
    url = "http://localhost:11434/api/chat"
    
    body = %{
      "model" => "llama2",
      "messages" => [
        %{"role" => "user", "content" => "Say hello in one word"}
      ],
      "stream" => false
    }
    
    case Req.post(url, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: response}} ->
        IO.puts("✓ Chat request successful!")
        IO.puts("Response: #{response["message"]["content"]}")
        
      {:ok, %{status: 404}} ->
        IO.puts("✗ Model 'llama2' not found")
        IO.puts("Pull it with: ollama pull llama2")
        
      {:ok, %{status: status, body: body}} ->
        IO.puts("✗ Request failed with status #{status}")
        IO.puts("Error: #{inspect(body)}")
        
      {:error, reason} ->
        IO.puts("✗ Request failed: #{inspect(reason)}")
    end
  end
end

# Run tests
OllamaTest.test_connection()
OllamaTest.test_chat_request()