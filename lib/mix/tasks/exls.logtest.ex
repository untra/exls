defmodule Mix.Tasks.Exls.Logtest do
  use Mix.Task

  @shortdoc "Runs a short test"

  @moduledoc """
  Runs a test of the logging mechanisms
  """

  @doc false
  def run(args) do
    # Application.put_env(:elixirls, :serve_endpoints, true, persistent: true)
    # Mix.Tasks.Run.run run_args() ++ args
    Mix.Tasks.Run.run run_args() ++ args
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?
  end
end
