defmodule ExLS.Debugger do
  @moduledoc """
  Debugger adapter for Elixir Mix tasks using VS Code Debug Protocol
  """

  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # children commented out due to wacky bugs and changing protocols. sit tight.

    children = [
      # Define workers and child supervisors to be supervised
      # worker(ExLS.Debugger.Output, [ExLS.Debugger.Output]),
      # worker(ExLS.Debugger.OutputDevice,
      #        [:user, "stdout", [change_all_gls?: change_all_gls?()]],
      #        [id: ExLS.Debugger.OutputDevice.Stdout]),
      # worker(ExLS.Debugger.OutputDevice, [:standard_error, "stderr"],
      #        [id: ExLS.Debugger.OutputDevice.Stderr]),
      # worker(ExLS.Debugger.Server, [[name: ExLS.Debugger.Server]]),
      # worker(ExLS.IOHandler, [ExLS.Debugger.Server, [name: ExLS.Debugger.IOHandler]]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExLS.Debugger.Supervisor, max_restarts: 0]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    :init.stop
  end

  defp change_all_gls? do
    !(Enum.any?(Application.started_applications, &match?({:mix, _, _}, &1)) and Mix.env == :test)
  end
end
