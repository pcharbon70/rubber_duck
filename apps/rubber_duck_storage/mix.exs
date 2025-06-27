defmodule RubberDuckStorage.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/rubber_duck"

  def project do
    [
      app: :rubber_duck_storage,
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
      name: "RubberDuck Storage",
      description:
        "Data persistence layer with Ecto and PostgreSQL for RubberDuck coding assistant",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "RubberDuckStorage",
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
      mod: {RubberDuckStorage.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19.0"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Umbrella dependencies
      {:rubber_duck_core, in_umbrella: true}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      # Ecto aliases
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --warnings-as-errors"],
      "test.watch": ["test.watch --warnings-as-errors"]
    ]
  end

  defp preferred_cli_env do
    [
      "ecto.setup": :dev,
      "ecto.reset": :dev,
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
