defmodule RubberDuck.MixProject do
  use Mix.Project

  def project do
    [
      app: :rubber_duck,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia, :syn],
      mod: {RubberDuck.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:libcluster, "~> 3.4"},
      {:cachex, "~> 3.6"},
      {:nebulex, "~> 2.6"},
      {:nebulex_adapters_cachex, "~> 2.1"},
      {:gen_stage, "~> 1.2"},
      {:flow, "~> 1.2"},
      {:horde, "~> 0.8"},
      {:syn, "~> 3.3"}
      # Multi-language parsing will be implemented with native Elixir parsers
      # and simulated Tree-sitter interface for demonstration

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end