defmodule RubberDuckEngines.MixProject do
  use Mix.Project

  def project do
    [
      app: :rubber_duck_engines,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      # Inter-app dependencies
      {:rubber_duck_core, in_umbrella: true},
      
      # Analysis dependencies
      {:jason, "~> 1.4"}
    ]
  end
end
