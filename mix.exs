defmodule RubberDuck.Umbrella.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/rubber_duck"

  def project do
    [
      apps_path: "apps",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env(),
      test_coverage: [tool: ExCoveralls],
      
      # Docs
      name: "RubberDuck",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Dependencies listed here are only for configuration
  # and cannot be accessed from applications inside the apps folder.
  # These are shared development dependencies for all umbrella apps
  defp deps do
    [
      # Development & Testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases do
    [
      # Setup all apps
      setup: ["deps.get", "cmd mix setup"],
      
      # Run tests in all apps
      test: ["cmd mix test"],
      
      # Check code quality
      quality: [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors",
        "cmd mix compile --warnings-as-errors"
      ],
      
      # Run all checks before committing
      check: ["quality", "test"],
      
      # Generate documentation
      docs: ["cmd mix docs", "docs"],
      
      # Format all files
      "format.all": ["format", "cmd mix format"]
    ]
  end

  defp preferred_cli_env do
    [
      check: :test,
      quality: :test,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end
end