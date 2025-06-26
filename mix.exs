defmodule RubberDuck.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Dependencies listed here are only for configuration
  # and cannot be accessed from applications inside the apps folder.
  defp deps do
    []
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases do
    [
      # Runs setup in all child apps
      setup: ["cmd mix setup"]
    ]
  end
end