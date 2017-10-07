defmodule ExLS.LanguageServer.Protocol do
  @moduledoc """
  Macros for requests and notifications in the Language Server Protocol
  """

  import ExLS.LanguageServer.JsonRpc

  defmacro __using__(_) do
    quote do
      import ExLS.LanguageServer.JsonRpc
      import unquote(__MODULE__)
    end
  end

  defmacro cancel_request(id) do
    quote do
      notification("$/cancelRequest", %{"id" => unquote(id)})
    end
  end

  defmacro did_open(uri, language_id, version, text) do
    quote do
      notification("textDocument/didOpen",
        %{"textDocument" => %{"uri" => unquote(uri), "languageId" => unquote(language_id),
            "version" => unquote(version), "text" => unquote(text)}})
    end
  end

  defmacro did_close(uri) do
    quote do
      notification("textDocument/didOpen", %{"textDocument" => %{"uri" => unquote(uri)}})
    end
  end

  defmacro did_change(uri, version, content_changes) do
    quote do
      notification("textDocument/didChange", %{"textDocument" => %{"uri" => unquote(uri),
          "version" => unquote(version)}, "contentChanges" => unquote(content_changes)})
    end
  end

  defmacro did_change_configuration(settings) do
    quote do
      notification("workspace/didChangeConfiguration", %{"settings" => unquote(settings)})
    end
  end

  defmacro did_change_watched_files(changes) do
    quote do
      notification("workspace/didChangeWatchedFiles", %{"changes" => unquote(changes)})
    end
  end

  defmacro did_save(uri) do
    quote do
      notification("textDocument/didSave", %{"textDocument" => %{"uri" => unquote(uri)}})
    end
  end

  defmacro initialize_req(id, root_uri, client_capabilities) do
    quote do
      request(unquote(id), "initialize", %{
        "capabilities" => unquote(client_capabilities),
        "rootUri" => unquote(root_uri)
      })
    end
  end

  defmacro hover_req(id, uri, line, character) do
    quote do
      request(unquote(id), "textDocument/hover", %{"textDocument" => %{"uri" => unquote(uri)},
          "position" => %{"line" => unquote(line), "character" => unquote(character)}})
    end
  end

  defmacro definition_req(id, uri, line, character) do
    quote do
      request(unquote(id), "textDocument/definition", %{"textDocument" => %{"uri" => unquote(uri)},
          "position" => %{"line" => unquote(line), "character" => unquote(character)}})
    end
  end

  defmacro completion_req(id, uri, line, character) do
    quote do
      request(unquote(id), "textDocument/completion", %{"textDocument" => %{"uri" => unquote(uri)},
          "position" => %{"line" => unquote(line), "character" => unquote(character)}})
    end
  end
end
