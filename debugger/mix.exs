defmodule ExLS.Debugger.Mixfile do
  use Mix.Project

  def project do
    [app: :debugger,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.5",
     build_embedded: false,
     start_permanent: true,
     build_per_environment: false,
     consolidate_protocols: false,
     deps: deps(),
     escript: escript()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [mod: {ExLS.Debugger, []}, applications: []]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:my_app, in_umbrella: true}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:elixir_sense, "~> 1.0"},
     {:io_handler, in_umbrella: true}]
  end

  defp escript do
    [main_module: ExLS.Debugger.CLI,
     embed_elixir: false,
     path: "../../release/debugger",
     strip_beam: false,
     comment: escript_comment()]
  end

  defp escript_comment do
    "Requires Elixir but does not embed it. Run via the included exscript.sh (Unix) or \
     exscript.bat (Windows, TODO) scripts to set ERL_LIBS."
  end
end
