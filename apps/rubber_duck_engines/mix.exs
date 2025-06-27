defmodule RubberDuckEngines.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/rubber_duck"

  def project do
    [
      app: :rubber_duck_engines,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),

      # Docs
      name: "RubberDuck Engines",
      description: "Extensible analysis engine framework for code analysis, documentation, and testing for RubberDuck",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "RubberDuckEngines",
        extras: ["README.md"]
      ],

      # Package
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RubberDuckEngines.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Umbrella dependencies
      {:rubber_duck_core, in_umbrella: true},
      {:rubber_duck_storage, in_umbrella: true},
      
      # Analysis dependencies
      {:jason, "~> 1.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["test --warnings-as-errors"],
      "test.watch": ["test.watch --warnings-as-errors"]
    ]
  end

  defp preferred_cli_env do
    [
      "test.watch": :test,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Pascal Charbonneau"]
    ]
  end
end
