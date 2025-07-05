defmodule RubberDuck.MixProject do
  use Mix.Project

  def project do
    [
      app: :rubber_duck,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RubberDuck.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash_postgres, "~> 2.0"},
      {:usage_rules, "~> 0.1", only: [:dev]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:tower, "~> 0.6"},
      {:tower_email, "~> 0.6"},
      {:tower_slack, "~> 0.6"},
      {:hackney, "~> 1.20"},
      {:poolboy, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      
      # LLM Integration dependencies
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:tesla, "~> 1.8"},
      {:finch, "~> 0.18"},
      {:fuse, "~> 2.5"},  # Circuit breaker library
      {:ex_rated, "~> 2.1"},
      {:tiktoken, "~> 0.4"},  # OpenAI tokenization
      {:tokenizers, "~> 0.5"}  # HuggingFace tokenizers for Anthropic
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases() do
    [test: ["ash.setup --quiet", "test"], setup: "ash.setup"]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
