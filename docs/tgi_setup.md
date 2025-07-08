# Text Generation Inference (TGI) Provider Setup Guide

## Overview

The TGI provider enables RubberDuck to use Hugging Face's Text Generation Inference server for high-performance, production-ready LLM inference. TGI provides optimized inference with Flash Attention, Paged Attention, and advanced features like function calling and guided generation.

## What is TGI?

Text Generation Inference (TGI) is a Rust-based inference server developed by Hugging Face for serving Large Language Models. It's designed for production workloads with features like:

- **High Performance**: Flash Attention, Paged Attention, and tensor parallelism
- **Scalability**: Efficient batching and concurrent request handling
- **Flexibility**: Support for any compatible HuggingFace model
- **Advanced Features**: Function calling, guided generation, JSON schema support
- **Dual APIs**: OpenAI-compatible and native TGI endpoints

## Prerequisites

### 1. Hardware Requirements

**Minimum:**
- 8GB GPU memory (for 7B models)
- 16GB+ RAM
- Modern CPU with AVX2 support

**Recommended:**
- 16GB+ GPU memory (for 13B models)
- 32GB+ RAM
- NVIDIA GPU with CUDA support

**For Large Models (70B+):**
- Multi-GPU setup (A100, H100)
- 80GB+ GPU memory
- High-bandwidth interconnect

### 2. Software Dependencies

**Docker (Recommended):**
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install NVIDIA Container Toolkit (for GPU support)
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update && apt-get install -y nvidia-docker2
systemctl restart docker
```

**From Source:**
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install Python dependencies
pip install torch transformers accelerate
```

## Installation

### Method 1: Docker (Recommended)

**For Standard Models (7B-13B):**
```bash
# Pull TGI Docker image
docker pull ghcr.io/huggingface/text-generation-inference:latest

# Run TGI with Llama 3.1 8B
docker run --gpus all --shm-size 1g -p 8080:80 \
  -v $PWD/data:/data \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --max-input-length 4096 \
  --max-total-tokens 8192
```

**For Large Models (70B+):**
```bash
# Multi-GPU setup
docker run --gpus all --shm-size 1g -p 8080:80 \
  -v $PWD/data:/data \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-70B-Instruct \
  --num-shard 4 \
  --max-input-length 4096 \
  --max-total-tokens 8192
```

### Method 2: From Source

```bash
# Clone TGI repository
git clone https://github.com/huggingface/text-generation-inference.git
cd text-generation-inference

# Build and install
cargo build --release
./target/release/text-generation-inference \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --port 8080
```

### Method 3: Using Hugging Face Hub

```bash
# Install TGI from PyPI
pip install text-generation

# Launch TGI server
text-generation-launcher \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --port 8080
```

## Configuration

### Basic Configuration

TGI is already configured in RubberDuck's `config/llm.exs`:

```elixir
%{
  name: :tgi,
  adapter: RubberDuck.LLM.Providers.TGI,
  base_url: System.get_env("TGI_BASE_URL", "http://localhost:8080"),
  models: ["llama-3.1-8b", "mistral-7b", "codellama-13b"],
  priority: 4,
  timeout: 120_000,
  options: [
    supports_function_calling: true,
    supports_guided_generation: true,
    supports_json_mode: true
  ]
}
```

### Environment Variables

```bash
# TGI server URL
export TGI_BASE_URL="http://localhost:8080"

# Optional: HuggingFace API token for private models
export HUGGING_FACE_HUB_TOKEN="your-hf-token"
```

### Model Configuration

Update the model list based on your TGI deployment:

```elixir
models: [
  "llama-3.1-8b",      # Meta Llama 3.1 8B
  "llama-3.1-70b",     # Meta Llama 3.1 70B
  "mistral-7b",        # Mistral 7B
  "mixtral-8x7b",      # Mixtral 8x7B
  "codellama-13b",     # CodeLlama 13B
  "falcon-40b",        # Falcon 40B
  "starcoder2-15b"     # StarCoder2 15B
]
```

## Popular Models

### Code Generation
```bash
# CodeLlama 13B
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id codellama/CodeLlama-13b-Instruct-hf

# StarCoder2 15B
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id bigcode/starcoder2-15b
```

### General Purpose
```bash
# Mistral 7B
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id mistralai/Mistral-7B-Instruct-v0.3

# Mixtral 8x7B (Mixture of Experts)
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id mistralai/Mixtral-8x7B-Instruct-v0.1
```

### Specialized Models
```bash
# Falcon 40B
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id tiiuae/falcon-40b-instruct

# Zephyr 7B (Helpful assistant)
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id HuggingFaceH4/zephyr-7b-beta
```

## Usage

### Basic Completion

```elixir
# TGI will be used based on priority and model availability
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "llama-3.1-8b",
  messages: [
    %{role: "user", content: "Explain quantum computing in simple terms"}
  ]
})

IO.puts(response.content)
```

### Forcing TGI Provider

```elixir
# Explicitly use TGI
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  provider: :tgi,
  model: "mistral-7b",
  messages: [
    %{role: "user", content: "Write a Python function to sort a list"}
  ]
})
```

### Code Generation with CodeLlama

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "codellama-13b",
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
  model: "llama-3.1-8b",
  messages: [%{role: "user", content: "Tell me a story"}]
})

stream
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()
```

### Function Calling

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "llama-3.1-8b",
  messages: [
    %{role: "user", content: "What's the weather like in San Francisco?"}
  ],
  options: %{
    tools: [
      %{
        type: "function",
        function: %{
          name: "get_weather",
          description: "Get current weather information",
          parameters: %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "City name"}
            },
            required: ["location"]
          }
        }
      }
    ],
    tool_choice: "auto"
  }
})
```

### Guided Generation (JSON Mode)

```elixir
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  model: "mistral-7b",
  messages: [
    %{role: "user", content: "Generate a person's profile"}
  ],
  options: %{
    json_mode: true,
    schema: %{
      type: "object",
      properties: %{
        name: %{type: "string"},
        age: %{type: "integer"},
        occupation: %{type: "string"},
        hobbies: %{type: "array", items: %{type: "string"}}
      },
      required: ["name", "age"]
    }
  }
})

# Response will be valid JSON
{:ok, data} = Jason.decode(response.content)
```

## Advanced Configuration

### Performance Tuning

```bash
# Optimize for throughput
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --max-batch-prefill-tokens 8192 \
  --max-batch-total-tokens 16384 \
  --max-waiting-tokens 20

# Optimize for latency
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --max-batch-prefill-tokens 4096 \
  --max-batch-total-tokens 8192 \
  --max-waiting-tokens 0
```

### Memory Optimization

```bash
# Enable quantization for lower memory usage
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --quantize bitsandbytes-nf4

# Use Flash Attention v2
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-8B-Instruct \
  --flash-attention
```

### Multi-GPU Setup

```bash
# Tensor parallelism across multiple GPUs
docker run --gpus all --shm-size 1g -p 8080:80 \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-70B-Instruct \
  --num-shard 4 \
  --max-input-length 4096 \
  --max-total-tokens 8192
```

## Monitoring and Health Checks

### Health Check

```elixir
config = %RubberDuck.LLM.ProviderConfig{
  base_url: "http://localhost:8080"
}

{:ok, health} = RubberDuck.LLM.Providers.TGI.health_check(config)
IO.inspect(health)
# %{
#   status: :healthy,
#   model: "llama-3.1-8b",
#   message: "TGI server is healthy and serving model"
# }
```

### Manual Health Check

```bash
# Check TGI server health
curl http://localhost:8080/health

# Get model information
curl http://localhost:8080/info

# Check server metrics
curl http://localhost:8080/metrics
```

## Troubleshooting

### Common Issues

#### 1. Connection Refused
```elixir
# Error: {:error, {:connection_error, :econnrefused}}
```

**Solution**: Ensure TGI server is running:
```bash
# Check if TGI is running
curl http://localhost:8080/health

# Check Docker containers
docker ps | grep text-generation-inference
```

#### 2. Model Loading Issues
```elixir
# Error: {:error, {:http_error, 503}}
```

**Solution**: Wait for model to finish loading:
```bash
# Check server logs
docker logs <container-id>

# Model loading can take 5-10 minutes for large models
```

#### 3. Out of Memory Errors
```bash
# Error: CUDA out of memory
```

**Solutions**:
```bash
# Use quantization
--quantize bitsandbytes-nf4

# Reduce batch size
--max-batch-prefill-tokens 2048

# Use smaller model
--model-id meta-llama/Llama-3.1-8B-Instruct  # instead of 70B
```

#### 4. Slow Responses
```elixir
# Error: {:error, :timeout}
```

**Solutions**:
```elixir
# Increase timeout in config
timeout: 300_000  # 5 minutes

# Optimize TGI settings
--max-waiting-tokens 0
--max-batch-total-tokens 4096
```

#### 5. Function Calling Not Working
```elixir
# Error: Function calls not being recognized
```

**Solutions**:
- Use models that support function calling (Llama 3.1, Mistral)
- Ensure proper tool schema format
- Check model supports guided generation

### Performance Optimization

#### GPU Utilization
```bash
# Monitor GPU usage
nvidia-smi -l 1

# Check GPU memory usage
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

#### Memory Usage
```bash
# Monitor system memory
htop

# Check Docker container memory
docker stats <container-id>
```

#### Request Latency
```bash
# Benchmark TGI performance
curl -X POST http://localhost:8080/generate \
  -H "Content-Type: application/json" \
  -d '{"inputs": "Hello", "parameters": {"max_new_tokens": 100}}' \
  -w "Time: %{time_total}s\n"
```

## Best Practices

### 1. Model Selection
- **7B models**: Good balance of quality and speed
- **13B models**: Better quality, moderate speed
- **70B models**: Best quality, slower inference

### 2. Deployment
- Use Docker for consistent environments
- Enable GPU support for better performance
- Use quantization for memory-constrained setups

### 3. Configuration
- Set appropriate timeouts based on model size
- Configure batch sizes based on GPU memory
- Enable Flash Attention for better performance

### 4. Monitoring
- Monitor GPU utilization and memory usage
- Set up health checks for production deployments
- Use metrics endpoint for performance monitoring

### 5. Error Handling
- Implement fallback providers for reliability
- Handle connection errors gracefully
- Set appropriate retry policies

## Production Deployment

### Docker Compose

```yaml
version: '3.8'
services:
  tgi:
    image: ghcr.io/huggingface/text-generation-inference:latest
    ports:
      - "8080:80"
    environment:
      - HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}
    volumes:
      - ./data:/data
    command: >
      --model-id meta-llama/Llama-3.1-8B-Instruct
      --max-input-length 4096
      --max-total-tokens 8192
      --max-batch-prefill-tokens 4096
      --flash-attention
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tgi-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tgi
  template:
    metadata:
      labels:
        app: tgi
    spec:
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:latest
        ports:
        - containerPort: 80
        env:
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: token
        args:
        - --model-id
        - meta-llama/Llama-3.1-8B-Instruct
        - --max-input-length
        - "4096"
        - --max-total-tokens
        - "8192"
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            memory: "16Gi"
            cpu: "4"
```

## Integration with RubberDuck Features

### Code Analysis
```elixir
# Use TGI for code analysis
{:ok, analysis} = RubberDuck.Analysis.Analyzer.analyze_with_llm(
  code,
  provider: :tgi,
  model: "codellama-13b"
)
```

### RAG with TGI
```elixir
# Use TGI for retrieval-augmented generation
{:ok, result} = RubberDuck.Workflows.RAG.execute(%{
  query: "How do I implement GenServers?",
  provider: :tgi,
  model: "llama-3.1-8b"
})
```

## Security Considerations

### Network Security
- Run TGI behind a reverse proxy
- Use HTTPS for external access
- Implement rate limiting
- Restrict access to authorized users

### Data Privacy
- All processing happens on your infrastructure
- No data sent to external services
- Models run locally with full control

### Model Security
- Use official HuggingFace models
- Verify model checksums
- Keep TGI updated to latest version

## Conclusion

The TGI provider brings production-ready, high-performance LLM inference to RubberDuck. With support for both OpenAI-compatible and native APIs, advanced features like function calling, and excellent performance optimizations, TGI is ideal for demanding AI applications that require speed, reliability, and full control over the inference process.