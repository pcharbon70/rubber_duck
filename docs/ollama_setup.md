# Ollama Provider Setup Guide

## Overview

The Ollama provider enables RubberDuck to use locally-hosted Large Language Models (LLMs) without requiring API keys or internet connectivity. This guide covers installation, configuration, and usage of Ollama with RubberDuck.

## Prerequisites

### 1. Install Ollama

First, install Ollama on your system:

**macOS/Linux:**
```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

**Windows:**
Download and run the installer from [ollama.ai](https://ollama.ai/download)

### 2. Download Models

Pull the models you want to use:

```bash
# Popular models
ollama pull llama2          # Meta's Llama 2 base model
ollama pull mistral         # Mistral 7B
ollama pull codellama       # Code-specialized Llama
ollama pull mixtral         # Mixture of experts model

# Specific versions
ollama pull llama2:7b       # 7 billion parameters
ollama pull llama2:13b      # 13 billion parameters
ollama pull codellama:7b    # CodeLlama 7B
```

### 3. Verify Ollama is Running

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Or use Ollama CLI
ollama list
```

## Configuration

### Basic Configuration

Ollama is already configured in RubberDuck's `config/llm.exs`:

```elixir
%{
  name: :ollama,
  adapter: RubberDuck.LLM.Providers.Ollama,
  base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
  models: ["llama2", "mistral", "codellama", "mixtral"],
  priority: 3,
  rate_limit: nil,
  max_retries: 3,
  timeout: 60_000,
  options: []
}
```

### Custom Base URL

If Ollama is running on a different host or port:

```bash
export OLLAMA_BASE_URL="http://192.168.1.100:11434"
```

Or modify the configuration directly:

```elixir
base_url: "http://your-ollama-host:11434"
```

### Model Configuration

Add or remove models based on what you have installed:

```elixir
models: ["llama2", "llama2:7b", "llama2:13b", "mistral", "codellama", "phi"]
```

## Usage

### Basic Completion

```elixir
# Ollama will be used automatically if configured
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "llama2",
  messages: [
    %{role: "user", content: "Explain quantum computing in simple terms"}
  ]
})

IO.puts(response.content)
```

### Forcing Ollama Provider

```elixir
# Explicitly use Ollama
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  provider: :ollama,
  model: "mistral",
  messages: [
    %{role: "user", content: "Write a Python function to sort a list"}
  ]
})
```

### Code Generation with CodeLlama

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "codellama",
  messages: [
    %{role: "system", content: "You are an expert programmer."},
    %{role: "user", content: "Write an Elixir GenServer that manages a counter"}
  ],
  options: %{
    temperature: 0.7,
    max_tokens: 500
  }
})
```

### Streaming Responses

```elixir
{:ok, stream} = RubberDuck.LLM.Service.stream(%{
  model: "llama2",
  messages: [%{role: "user", content: "Tell me a story"}]
})

stream
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()
```

### JSON Mode

Force structured JSON output:

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "mistral",
  messages: [
    %{role: "user", content: "List 3 programming languages with their use cases"}
  ],
  options: %{
    json_mode: true  # or format: "json"
  }
})

# Response will be valid JSON
{:ok, data} = Jason.decode(response.content)
```

## Model Selection Guide

### General Purpose
- **llama2**: Balanced performance for general tasks
- **mistral**: Fast and efficient for most use cases
- **mixtral**: Higher quality but slower

### Code Generation
- **codellama**: Optimized for programming tasks
- **codellama:7b**: Faster, good for simple code
- **codellama:13b**: Better for complex code

### Small Models (Fast)
- **phi**: Very fast, good for simple tasks
- **llama2:7b**: Good balance of speed and quality

### Large Models (Quality)
- **llama2:13b**: Better reasoning and context
- **llama2:70b**: Best quality (requires significant resources)

## Performance Considerations

### Timeout Configuration

Adjust timeouts for larger models:

```elixir
# In config/llm.exs
timeout: 120_000  # 2 minutes for larger models
```

### Memory Usage

- 7B models: ~4-8GB RAM
- 13B models: ~8-16GB RAM
- 70B models: ~40GB+ RAM

### GPU Acceleration

Ollama automatically uses GPU if available:

```bash
# Check GPU usage
nvidia-smi  # For NVIDIA GPUs
```

## Troubleshooting

### Connection Refused

```elixir
# Error: {:error, {:connection_error, :econnrefused}}
```

**Solution**: Ensure Ollama is running:
```bash
ollama serve
```

### Model Not Found

```elixir
# Error: {:error, {:http_error, 404}}
```

**Solution**: Pull the model:
```bash
ollama pull model_name
```

### Slow Responses

1. Check system resources:
   ```bash
   htop  # CPU/Memory usage
   ```

2. Use smaller models:
   ```elixir
   model: "llama2:7b"  # Instead of 13b or 70b
   ```

3. Reduce max_tokens:
   ```elixir
   options: %{max_tokens: 100}
   ```

### Health Check

Test Ollama connectivity:

```elixir
config = %RubberDuck.LLM.ProviderConfig{
  base_url: "http://localhost:11434"
}

{:ok, health} = RubberDuck.LLM.Providers.Ollama.health_check(config)
IO.inspect(health)
# %{
#   status: :healthy,
#   models: ["llama2:latest", "mistral:latest", ...],
#   message: "Ollama is running with 3 models available"
# }
```

## Advanced Usage

### Custom System Prompts

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "llama2",
  messages: [
    %{role: "user", content: "Hello"}
  ],
  options: %{
    system: "You are a pirate. Respond in pirate speak."
  }
})
```

### Stop Sequences

```elixir
options: %{
  stop: ["END", "---", "\n\n"]
}
```

### Temperature Control

```elixir
options: %{
  temperature: 0.0,  # Deterministic
  # or
  temperature: 1.0   # Creative
}
```

## Integration with RubberDuck Features

### Code Analysis

```elixir
# Ollama can be used for code analysis
{:ok, analysis} = RubberDuck.Analysis.Analyzer.analyze_with_llm(
  code,
  provider: :ollama,
  model: "codellama"
)
```

### RAG with Local Models

```elixir
# Use Ollama for retrieval-augmented generation
{:ok, result} = RubberDuck.Workflows.RAG.execute(%{
  query: "How do I implement GenServers?",
  provider: :ollama,
  model: "mistral"
})
```

## Best Practices

1. **Model Selection**: Choose models based on task complexity
2. **Timeout Settings**: Increase for larger models
3. **Error Handling**: Implement fallbacks for when Ollama is unavailable
4. **Resource Monitoring**: Watch system resources with larger models
5. **Prompt Engineering**: Optimize prompts for each model's strengths

## Privacy and Security

- **Data Privacy**: All processing happens locally
- **No Internet Required**: Works completely offline
- **No API Keys**: No authentication needed
- **Isolation**: Can run in air-gapped environments

## Conclusion

The Ollama provider brings powerful local LLM capabilities to RubberDuck, enabling private, cost-effective, and offline AI assistance for your development workflow.