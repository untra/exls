defmodule ExLS do
  @moduledoc """
  Implementation of Language Server Protocol for Elixir
  """
  use Application

  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      {ExLS.LanguageServer.Builder, [ExLS.LanguageServer.Builder]},
      {ExLS.LanguageServer.Server, [ExLS.LanguageServer.Server]},
      {ExLS.IOHandler,
             [ExLS.LanguageServer.Server, [name: ExLS.LanguageServer.IOHandler]]},
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExLS.LanguageServer.Supervisor, max_restarts: 0]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    :init.stop
  end

  def logTest do
    Logger.info "This is an info message in the real thing"
    Logger.debug "This is a debug message in the real thing"
    Logger.warn "This is a warning message in the real thing"
    Logger.error "This is an error message in the real thing"
  end
end

