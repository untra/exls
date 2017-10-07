defmodule ExLS.LanguageServer.Builder do
  @moduledoc """
  Server that compiles the current Mix project

  This is implemented as a GenServer because builds are not parallelizable. Only one instance of
  this server should be run to avoid conflicts between builds. (This is mostly an issue during
  tests, not during actual use.)
  """
  use GenServer
  alias ExLS.LanguageServer.{BuildError, JsonRpc}
  alias ExLS.LanguageServer.Compilers.Elixir, as: EC
  require Logger

  @build_path ".exls/build"

  ## Client API

  def child_spec(args) do
    %{
      name: args[:name],
      id: __MODULE__,
      start: { __MODULE__, :start_link, args},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link(name \\ nil) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def build(server \\ __MODULE__, source_files) do
    GenServer.call(server, {:build, source_files}, :infinity)
  end

  def clean(server \\ __MODULE__, path) do
    GenServer.call(server, {:clean, path}, :infinity)
  end

  ## Server Callbacks

  def handle_call({:build, source_files}, _from, state) do
    configs = Mix.Project.config_files ++ Mix.Tasks.Compile.Erlang.manifests
    force = Mix.Project.get() == nil or
              Mix.Utils.stale?(configs, ExLS.LanguageServer.Compilers.Elixir.manifests)
    if force do
      Logger.info("Forcing full rebuild")
      reload_project()
    end

    response =
      try do
        build_errors =
          if Mix.Project.umbrella? do
            recur(fn(project) -> do_build(project, source_files) end)
            |> List.flatten()
          else
            do_build(Mix.Project.get!(), source_files)
          end
        {:ok, build_errors}
      rescue
        err -> {:error, err}
      end
    {:reply, response, state}
  end

  def handle_call({:clean, path}, _from, state) do
    File.rm_rf(Path.join([path, @build_path]))
    {:reply, :ok, state}
  end

  # For some unknown reason, this server sometimes receives bizarre casts while performing builds.
  # This is a noop to avoid crashing when receiving these unwanted casts.
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def terminate(reason, state) do
    unless reason == :normal do
      msg = "Elixir Language Server terminated abnormally because "
        <> Exception.format_exit(reason)
      JsonRpc.show_message(:error, msg)
    end
    super(reason, state)
  end

  ## Helpers

  defp recur(fun) do
    # Get all dependency configuration but not the deps path
    # as we leave the control of the deps path still to the
    # umbrella child.
    config = Mix.Project.deps_config |> Keyword.delete(:deps_path)
    for %Mix.Dep{app: app, opts: opts} <- Mix.Dep.Umbrella.loaded do
      Mix.Project.in_project(app, opts[:path], config, fun)
    end
  end

  defp do_build(_project, source_files, opts \\ []) do
    compilers = Mix.Tasks.Compile.compilers()

    Mix.shell(Mix.Shell.Quiet)
    Enum.flat_map compilers, fn compiler ->
      case compiler do
        # :app ->
        #   []
        :elixir ->
          compile_elixir(source_files, opts[:force])
        :xref ->
          compile_xref()
        _ ->
          Mix.Task.run("compile.#{compiler}", opts)
          []
      end
    end
  end

  defp reload_project do
    current_project = Mix.ProjectStack.pop()
    try do
      Mix.ProjectStack.post_config(build_path: @build_path)
      Code.load_file(System.get_env("MIX_EXS") || "mix.exs")
    rescue
      err ->
        Logger.error("Error loading project: " <> Exception.format_exit(err))
        case current_project do
          %{name: name, file: file, config: config} ->
            Mix.ProjectStack.push(name, config, file)
          _ ->
            nil
        end
    else
      _ -> Logger.info("Successfully reloaded the project")
    end
  end

  defp compile_elixir(changed_sources, force) do
    source_files = Enum.reject(Map.values(changed_sources), &is_nil/1)
    dest = Mix.Project.compile_path(Mix.Project.config)
    manifest = EC.manifest
    srcs = Mix.Project.config[:elixirc_paths]
    opts = [ignore_module_conflict: true]
    {_modules, sources} = EC.compile(manifest, srcs, source_files, dest, force, opts)
    build_errors(sources)
  end

  defp compile_xref do
    errors =
      ExLS.LanguageServer.Compilers.Xref.unreachable fn file, entries ->
        Enum.flat_map entries, fn {lines, error, module, function, arity} ->
          message =
            case error do
              :unknown_module ->
                to_string(["function ", Exception.format_mfa(module, function, arity),
                  " is undefined\n(module #{inspect module} is not available)\n"])
              :unknown_function ->
                to_string(["function ", Exception.format_mfa(module, function, arity),
                  " is undefined or private"])
            end

          for line <- lines do
            %BuildError{severity: :warn, line: line - 1, file: Path.absname(file),
              message: message, source: "xref"}
          end
        end
      end

    List.flatten(errors)
  end

  # The custom manifest format we use saves the errors and warnings generated by the build in the
  # "source" records.
  defp build_errors(elixir_manifest) do
    require EC
    Enum.flat_map elixir_manifest, fn source ->
      EC.source(error: error, warnings: warnings) = source
      case error do
        nil -> warnings
        _ -> [error | warnings]
      end
    end
  end
end
