defmodule ExLS.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixirls,
      version: version(),
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def version do
    "0.1.0"
  end

  defp aliases do
    [
      build: [ &build_releases/1],
    ]
  end

  defp build_releases(_) do
    Mix.Tasks.Compile.run([])
    Mix.Tasks.Archive.Build.run([])
    Mix.Tasks.Archive.Build.run(["--output=exls.ez"])
    File.rename("exls.ez", "./exls_archives/exls.ez")
    File.rename("exls-#{version()}.ez", "./exls_archives/exls-#{version()}.ez")
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      # {:jsonrpc2, "~> 1.0"},
      {:poison, "~> 3.0"},
      {:elixir_sense, "~> 1.0"},
      # {:ranch, "~> 1.3"}
    ]
  end
end
