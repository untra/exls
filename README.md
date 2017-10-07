# Elixir Language Server (ExLS)

*This is a very early release. It only works with Elixir 1.4, and it's only been tested on OSX. If all you want is a good, stable Elixir editor, stick with whatever you're using now until ExLS is more mature.*

The Elixir Language Server provides a server that runs in the background, providing IDEs, editors, and other tools with information about Elixir Mix projects. It adheres to the [Language Server Protocol](https://github.com/Microsoft/language-server-protocol), a standard supported by Microsoft and Red Hat for frontend-independent IDE support. Debugger integration is accomplished through the similar [VS Code Debug Protocol](https://code.visualstudio.com/docs/extensionAPI/api-debugging).

Features include:

- Debugger support!!!
- Inline reporting of build warnings and errors
- Documentation lookup on hover
- Go-to-definition
- Code completion

![Screenshot](screenshot.png?raw=true)

## IDE support

ExLS is intended to be frontend-independent, but at this point has only been tested with VS Code. You can install the VS Code extension by searching ExLS from the "extensions" pane. The plugin code resides in the [vscode-elixir-ls](https://github.com/JakeBecker/vscode-elixir-ls) repo.

## Debugger support

ExLS includes debugger support adhering to the [VS Code debugger protocol](https://code.visualstudio.com/docs/extensionAPI/api-debugging) which is closely related to the Language Server Protocol. At the moment, only line breakpoints are supported.

When debugging in Elixir or Erlang, only modules that have been "interpreted" (using `:int.ni/1` or `:int.i/1`) will accept breakpoints or show up in stack traces. The debugger in ExLS automatically interprets all modules in the Mix project and dependencies prior to launching the Mix task, so you can set breakpoints anywhere in your project or dependency modules.

In order to debug modules in `.exs` files (such as tests), they must be specified under `requireFiles` in your launch configuration so they can be loaded and interpreted prior to running the task. For example, the default launch configuration for "mix test" in the VS Code plugin looks like this:

```
{
  "type": "mix_task",
  "name": "mix test",
  "request": "launch",
  "task": "test",
  "taskArgs": ["--trace"],
  "projectDir": "${workspaceRoot}",
  "requireFiles": [
    "test/**/test_helper.exs",
    "test/**/*_test.exs"
  ]
}
```

## Automatic builds and error reporting

In order to provide features like documentation look-up and code completion, ExLS needs to be able to load your project's compiled modules. ExLS attempts to compile your project automatically and reports build errors and warnings in the editor.

At the moment, this compilation is performed using a fork of Elixir 1.4's compiler. This is not a good long-term solution and replacing it is a high priority in the near future. See [this blog post](https://medium.com/@JakeBeckerCode/compiler-hacks-in-elixirls-6a6f04834f66) for an explanation.

To avoid interfering with the developer's CLI workflow, ExLS creates a folder `.exls` in the project root and saves its build output there, so add `.exls` to your gitignore file.

Note that compiling untrusted Elixir files can be dangerous. Elixir can execute arbitrary code at compile time, which is how it can support such extensive metaprogramming. Consequently, compiling untrusted Elixir code is a lot like executing an untrusted script. Since ExLS compiles your code automatically, opening a project in an ExLS-enabled editor has the same risks as running `mix compile`. It's an unlikely attack vector, but worth being aware of.

## Contributing

While you can develop ExLS on its own, it's easiest to test out changes if you clone the [vscode-elixir-ls](https://github.com/JakeBecker/vscode-elixir-ls) repository instead. It includes ExLS as a Git submodule, so you can make your changes in the submodule directory and launch the extension from the parent directory via the included "Launch Extension" configuration in `launch.json`. See the README on that repo for more details.

### Building and running

You can run the apps with `mix run` from the `apps/language_server` or `apps/debugger` directories. To build for release, run the `release.sh` script. It compiles these two apps to escripts in the `release` folder.

Elixir escripts typically embed Elixir, which is not what we want because users will want to run it against their own system Elixir installation. In order to support this, there are scripts in the `bin` folder that look for the system-wide Elixir installation and set the `ERL_LIBS` environment variable prior to running the escripts. These scripts are copied to the `release` folder by `release.sh`.

## Acknowledgements and related projects

ExLS isn't the first frontend-independent server for Elixir language support. The original was [Alchemist Server](https://github.com/tonini/alchemist-server/), which powers the [Alchemist](https://github.com/tonini/alchemist.el) plugin for Emacs. Another project, [Elixir Sense](https://github.com/msaraiva/elixir_sense), builds upon Alchemist and powers the [Elixir plugin for Atom](https://github.com/msaraiva/atom-elixir) as well as another VS Code plugin, [VSCode Elixir](https://github.com/fr1zle/vscode-elixir). ExLS uses Elixir Sense for several code insight features. Credit for those projects goes to their respective authors.
