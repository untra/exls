defmodule ExLS.Debugger.Server do
  @moduledoc """
  Implements the VS Code Debug Protocol

  Refer to the protocol's [documentation](https://github.com/Microsoft/vscode/blob/master/src/vs/workbench/parts/debug/common/debugProtocol.d.ts)
  for details.

  The protocol specifies that we must assign unique IDs to "threads" (or processes), to stack
  frames, and to any variables that can be expanded. We keep a counter with the next ID to use and
  increment it any time we assign an ID.
  """

  alias ExLS.Debugger.{Output, Stacktrace, Protocol, Variables}
  use GenServer
  use Protocol

  require Logger

  @temp_beam_dir ".exls/temp_beams"

  defstruct [
    client_info: nil,
    config: %{},
    task_ref: nil,
    threads: %{},  # id => pid
    threads_inverse: %{},  # pid => id
    paused_processes: %{},  # pid => PausedProcess
    next_id: 1,
    output: Output,
    breakpoints: %{},  # path => [{module, line}]
  ]

  defmodule PausedProcess do
    defstruct [
      stack: nil,
      frames: %{},  # id => frame
      frames_inverse: %{},  # frame => id
      vars: %{},  # id => var
      vars_inverse: %{},  # var => id
    ]
  end

  ## Client API

  def start_link(opts \\ []) do
    name = opts[:name]
    opts = Keyword.delete(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def receive_packet(server \\ __MODULE__, packet) do
    GenServer.cast(server, {:receive_packet, packet})
  end

  def breakpoint_reached(pid, server) do
    GenServer.cast(server, {:breakpoint_reached, pid})
  end

  ## Server Callbacks

  def init(opts) do
    :int.start
    state = if opts[:output], do: %__MODULE__{output: opts[:output]}, else: %__MODULE__{}
    {:ok, state}
  end

  def handle_cast({:receive_packet, request(_, _) = packet}, state) do
    {response_body, state} = handle_request(packet, state)
    Output.send_response(packet, response_body)
    {:noreply, state}
  end

  def handle_cast({:breakpoint_reached, pid}, state) do
    {state, thread_id} = ensure_thread_id(state, pid)

    paused_process = %PausedProcess{stack: Stacktrace.get(pid)}
    state = put_in state.paused_processes[pid], paused_process

    body = %{"reason" => "breakpoint", "threadId" => thread_id, "allThreadsStopped" => false}
    Output.send_event("stopped", body)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    exit_code =
      case reason do
        :normal ->
          0
        _ ->
          IO.puts(:standard_error, "(Debugger) Task failed because " <>
            Exception.format_exit(reason))
          1
      end

    Output.send_event("exited", %{"exitCode" => exit_code})
    Output.send_event("terminated", %{"restart" => false})

    {:noreply, %{state | task_ref: nil}}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end

  def terminate(:normal, state) do
    super(:normal, state)
  end

  def terminate(reason, state) do
    IO.puts :standard_error, "Debug server terminated abnormally because " <>
        Exception.format_exit(reason)
    super(reason, state)
  end

  ## Helpers

  defp handle_request(initialize_req(_, client_info), state) do
    Logger.info("fdsa DEBUG")
    check_erlang_version()
    Process.group_leader(self(), Process.whereis(:user))
    {capabilities(), %{state | client_info: client_info}}
  end

  defp handle_request(launch_req(_, config), state) do
    Process.spawn(fn -> initialize(config) end, [:link])
    {%{}, %{state | config: config}}
  end

  defp handle_request(set_breakpoints_req(_, %{"path" => path}, breakpoints), state) do
    lines = for %{"line" => line} <- breakpoints, do: line
    new_breakpoints = resolve_breakpoint_modules(path, lines)
    for {module, _} <- new_breakpoints, module != nil, do: :int.ni(module)

    interpreted = :int.interpreted
    breakpoints_json =
      for {module, _} <- new_breakpoints do
        cond do
          module == nil ->
            %{"verified" => false,
              "message" => "Breakpoints can only be set in functions within modules"}
          not(module in interpreted) ->
            required_files = Enum.flat_map(state.config["requireFiles"] || [], &Path.wildcard/1)
            path = Path.relative_to_cwd(path)
            require_warning =
              if String.ends_with?(path, ".exs") and not(path in required_files) do
                "You may need to add #{path} to your launch configuration under \"requireFiles\""
              end
            %{"verified" => false,
              "message" => "Can't interpret module #{inspect(module)}. #{require_warning}"}
          true ->
            %{"verified" => true}
        end
      end

    new_verified_breakpoints =
      for {bp, %{"verified" => true}} <- List.zip([new_breakpoints, breakpoints_json]), do: bp

    existing_breakpoints = state.breakpoints[path] || []
    for {module, line} = bp <- existing_breakpoints,
        not(bp in new_verified_breakpoints), do: :int.delete_break(module, line)
    for {module, line} = bp <- new_verified_breakpoints,
        not(bp in existing_breakpoints), do: :int.break(module, line)

    state = put_in state.breakpoints[path], new_verified_breakpoints
    {%{"breakpoints" => breakpoints_json}, state}
  end

  defp handle_request(configuration_done_req(_), state) do
    server = :erlang.process_info(self())[:registered_name] || self()
    :int.auto_attach([:break], {__MODULE__, :breakpoint_reached, [server]})

    task = state.config["task"] || Mix.Project.config[:default_task]
    args = state.config["taskArgs"] || []
    {_pid, task_ref} = Process.spawn(fn -> launch_task(task, args) end, [:monitor])

    {%{}, %{state | task_ref: task_ref}}
  end

  defp handle_request(threads_req(_), state) do
    pids = :erlang.processes()
    {state, thread_ids} = ensure_thread_ids(state, pids)

    threads =
      for {pid, thread_id} <- List.zip([pids, thread_ids]), (info = Process.info(pid)) != nil do
        thread_info = Enum.into(info, %{})
        name =
          case Enum.into(thread_info, %{}) do
            %{:registered_name => registered_name} ->
              inspect(registered_name)
            %{:initial_call => {mod, func, arity}} ->
              "#{inspect(mod)}.#{to_string(func)}/#{arity}"
          end
        full_name = Enum.join([name, String.trim_leading(inspect(pid), "#PID")], " ")
        %{"id" => thread_id, "name" => full_name}
      end

    threads = Enum.sort_by threads, fn %{"name" => name} -> name end
    {%{"threads" => threads}, state}
  end

  defp handle_request(request(_, "stackTrace", %{"threadId" => thread_id} = args), state) do
    pid = state.threads[thread_id]
    paused_process = state.paused_processes[pid]

    total_frames = Enum.count(paused_process.stack)
    start_frame =
      case args do
        %{"startFrame" => start_frame} when is_integer(start_frame) -> start_frame
        _ -> 0
      end

    end_frame =
      case args do
        %{"levels" => levels} when is_integer(levels) and levels > 0 -> start_frame + levels
        _ -> -1
      end

    stack_frames = Enum.slice(paused_process.stack, start_frame..end_frame)
    {state, frame_ids} = ensure_frame_ids(state, pid, stack_frames)

    stack_frames_json =
      for {stack_frame, frame_id} <- List.zip([stack_frames, frame_ids]) do
        %{"id" => frame_id, "name" => Stacktrace.Frame.name(stack_frame),
          "line" => stack_frame.line, "column" => 0, "source" => %{"path" => stack_frame.file}}
      end

    {%{"stackFrames" => stack_frames_json, "totalFrames" => total_frames}, state}
  end

  defp handle_request(request(_, "scopes", %{"frameId" => frame_id}), state) do
    {pid, frame} = find_frame(state.paused_processes, frame_id)

    {state, args_id} = ensure_var_id(state, pid, frame.args)
    {state, bindings_id} = ensure_var_id(state, pid, frame.bindings)

    vars_scope =
      %{"name" => "variables", "variablesReference" => bindings_id,
        "namedVariables" => Enum.count(frame.bindings), "indexedVariables" => 0,
        "expensive" => false}

    args_scope =
      %{"name" => "arguments", "variablesReference" => args_id,
        "namedVariables" => 0, "indexedVariables" => Enum.count(frame.args),
        "expensive" => false}

    scopes = if (Enum.count(frame.args) > 0), do: [vars_scope, args_scope], else: [vars_scope]
    {%{"scopes" => scopes}, state}
  end

  defp handle_request(request(_, "variables", %{"variablesReference" => var_id} = args),
                     state) do

    {pid, var} = find_var(state.paused_processes, var_id)
    {state, vars_json} = variables(state, pid, var, args["start"], args["count"], args["filter"])

    {%{"variables" => vars_json}, state}
  end

  defp handle_request(request(_, "evaluate"), state) do
    msg = "(Debugger) Expression evaluation in Elixir debugger is not supported (yet)."
    {%{"result" => msg, "variablesReference" => 0}, state}
  end

  defp handle_request(request(_, "disconnect"), state) do
    System.halt(0)
    {%{}, state}
  end

  defp handle_request(continue_req(_, thread_id), state) do
    pid = state.threads[thread_id]
    state = remove_paused_process(state, pid)

    :int.continue(pid)
    {%{"allThreadsContinued" => false}, state}
  end

  defp handle_request(next_req(_, thread_id), state) do
    pid = state.threads[thread_id]
    state = remove_paused_process(state, pid)

    :int.next(pid)
    {%{}, state}
  end

  defp handle_request(step_in_req(_, thread_id), state) do
    pid = state.threads[thread_id]
    state = remove_paused_process(state, pid)

    :int.step(pid)
    {%{}, state}
  end

  defp handle_request(step_out_req(_, thread_id), state) do
    pid = state.threads[thread_id]
    state = remove_paused_process(state, pid)

    :int.finish(pid)
    {%{}, state}
  end

  defp remove_paused_process(state, pid) do
    update_in state.paused_processes, fn paused_processes ->
      Map.delete(paused_processes, pid)
    end
  end

  defp variables(state, pid, var, start, count, filter) do
    children =
      if (filter == "named" and Variables.child_type(var) == :indexed) or
          (filter == "indexed" and Variables.child_type(var) == :named) do
        []
      else
        Variables.children(var, start, count)
      end

    Enum.reduce children, {state, []}, fn {name, value}, {state, result} ->
      {state, var_id} =
        if Variables.expandable?(value) do
          ensure_var_id(state, pid, value)
        else
          {state, 0}
        end

      json =
        %{"name" => to_string(name), "value" => inspect(value), "variablesReference" => var_id,
          "type" => Variables.type(value)}
      json =
        case Variables.child_type(value) do
          :indexed -> Map.put(json, "indexedVariables", Variables.num_children(value))
          :named -> Map.put(json, "namedVariables", Variables.num_children(value))
          nil -> json
        end
      {state, result ++ [json]}
    end
  end

  defp find_var(paused_processes, var_id) do
    Enum.find_value paused_processes, fn {pid, paused_process} ->
      if Map.has_key?(paused_process.vars, var_id) do
        {pid, paused_process.vars[var_id]}
      end
    end
  end

  defp find_frame(paused_processes, frame_id) do
    Enum.find_value paused_processes, fn {pid, paused_process} ->
      if Map.has_key?(paused_process.frames, frame_id) do
        {pid, paused_process.frames[frame_id]}
      end
    end
  end

  defp ensure_thread_id(state, pid) do
    if Map.has_key?(state.threads_inverse, pid) do
      {state, state.threads_inverse[pid]}
    else
      id = state.next_id
      state = put_in(state.threads[id], pid)
      state = put_in(state.threads_inverse[pid], id)
      state = put_in(state.next_id, id + 1)
      {state, id}
    end
  end

  defp ensure_thread_ids(state, pids) do
    Enum.reduce pids, {state, []}, fn pid, {state, ids} ->
      {state, id} = ensure_thread_id(state, pid)
      {state, ids ++ [id]}
    end
  end

  defp ensure_var_id(state, pid, var) do
    if Map.has_key?(state.paused_processes[pid].vars_inverse, var) do
      {state, state.paused_processes[pid].vars_inverse[var]}
    else
      id = state.next_id
      state = put_in(state.paused_processes[pid].vars[id], var)
      state = put_in(state.paused_processes[pid].vars_inverse[var], id)
      state = put_in(state.next_id, id + 1)
      {state, id}
    end
  end

  defp ensure_frame_ids(state, pid, stack_frames) do
    Enum.reduce stack_frames, {state, []}, fn stack_frame, {state, ids} ->
      {state, id} = ensure_frame_id(state, pid, stack_frame)
      {state, ids ++ [id]}
    end
  end

  defp ensure_frame_id(state, pid, frame) do
    if Map.has_key?(state.paused_processes[pid].frames_inverse, frame) do
      {state, state.paused_processes[pid].frames_inverse[frame]}
    else
      id = state.next_id
      state = put_in(state.paused_processes[pid].frames[id], frame)
      state = put_in(state.paused_processes[pid].frames_inverse[frame], id)
      state = put_in(state.next_id, id + 1)
      {state, id}
    end
  end

  defp initialize(%{"projectDir" => project_dir} = config) do
    task = config["task"]
    task_args = config["taskArgs"]
    mix_env = config["mixEnv"]

    set_stack_trace_mode(config["stackTraceMode"])

    File.cd!(project_dir)
    Application.ensure_started(:mix)
    Mix.Local.append_archives
    Mix.Local.append_paths

    Code.load_file(System.get_env("MIX_EXS") || "mix.exs")
    task = task || Mix.Project.config[:default_task]
    unless mix_env, do: change_env(task)

    Mix.Tasks.Loadconfig.run([])
    Mix.Tasks.Deps.Loadpaths.run([])
    Mix.Tasks.Loadpaths.run([])
    unless is_list(task_args) and "--no-compile" in task_args do
      Mix.Tasks.Compile.run([])
    end

    # Reenable all tasks in case they're run from the debugged code
    for task <- Mix.Task.all_modules, do: Mix.Task.reenable(task)

    interpret_modules_in(Mix.Project.build_path)

    if required_files = config["requireFiles"], do: require_files(required_files)

    ExLS.Debugger.Output.send_event("initialized", %{})
  end

  defp set_stack_trace_mode("all"), do: :int.stack_trace(:all)
  defp set_stack_trace_mode("no_tail"), do: :int.stack_trace(:no_tail)
  defp set_stack_trace_mode("false"), do: :int.stack_trace(:false)
  defp set_stack_trace_mode(nil), do: nil

  defp set_stack_trace_mode(_) do
    IO.warn(~S(stackTraceMode must be "all", "no_tail", or "false"))
  end

  defp capabilities do
    %{"supportsConfigurationDoneRequest" => true,
		  "supportsFunctionBreakpoints" => false,
      "supportsConditionalBreakpoints" => false,
		  "supportsHitConditionalBreakpoints" => false,
		  "supportsEvaluateForHovers" => false,
		  "exceptionBreakpointFilters" => [],
		  "supportsStepBack" => false,
		  "supportsSetVariable" => false,
		  "supportsRestartFrame" => false,
		  "supportsGotoTargetsRequest" => false,
		  "supportsStepInTargetsRequest" => false,
		  "supportsCompletionsRequest" => false,
		  "supportsModulesRequest" => false,
		  "additionalModuleColumns" => [],
		  "supportedChecksumAlgorithms" => [],
		  "supportsRestartRequest" => false,
		  "supportsExceptionOptions" => false,
		  "supportsValueFormattingOptions" => false,
		  "supportsExceptionInfoRequest" => false,
		  "supportTerminateDebuggee" => false
    }
  end

  defp interpret_modules_in(path) do
    path
    |> Path.join("**/*.beam")
    |> Path.wildcard
    |> Enum.map(&(Path.basename(&1, ".beam") |> String.to_atom))
    |> Enum.filter(&(:int.interpretable(&1) == true && !:code.is_sticky(&1) && &1 != __MODULE__))
    |> Enum.map(&(:int.ni(&1)))
  end

  defp check_erlang_version do
    version = String.to_integer(to_string(:erlang.system_info(:otp_release)))
    if version < 19 do
      IO.warn "Erlang version >= OTP 19 is required to debug Elixir. " <>
          "(Current version: #{version})\n"
    end
  end

  defp change_env(task) do
    if env = preferred_cli_env(task) do
      Mix.env(env)
      if project = Mix.Project.pop do
        %{name: name, file: file} = project
        Mix.Project.push name, file
      end
    end
  end

  defp preferred_cli_env(task) do
    if System.get_env("MIX_ENV") do
      nil
    else
      task = String.to_atom(task)
      Mix.Project.config[:preferred_cli_env][task] || Mix.Task.preferred_cli_env(task)
    end
  end

  defp launch_task(task, args) do
    Process.group_leader(self(), Process.whereis(:user))
    Mix.Task.rerun(task, args)
  end

  # Interpreting modules defined in .exs files requires that we first load the file and save any
  # modules it defines to actual .beam files in the code path. The user must specify which .exs
  # files to load via the launch configuration. They must be in the correct order (for example,
  # test helpers before tests). We save the .beam files to a temporary folder which we add to the
  # code path.
  defp require_files(required_files) do
    File.rm_rf(@temp_beam_dir)
    File.mkdir_p(@temp_beam_dir)
    Code.append_path(Path.expand(@temp_beam_dir))

    required_files
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.flat_map(&Code.require_file/1)
    |> Enum.map(fn {module, beam_bin} -> save_and_reload(module, beam_bin) end)
  end

  defp save_and_reload(module, beam_bin) do
    File.write(Path.join(@temp_beam_dir, to_string(module) <> ".beam"), beam_bin)
    :code.delete(module)
    :int.ni(module)
  end

  defp resolve_breakpoint_modules(path, lines) do
    if Path.extname(path) == ".erl" do
      module = String.to_atom(Path.basename(path, ".erl"))
      for line <- lines, do: {module, line}
    else
      metadata = ElixirSense.Core.Parser.parse_file(path, false, false, nil)
      for line <- lines do
        env = ElixirSense.Core.Metadata.get_env(metadata, line)
        {env.module, line}
      end
    end
  end

end
