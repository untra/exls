defmodule ExLS.LanguageServer.Definition do
  @moduledoc """
  Go-to-definition provider utilizing Elixir Sense
  """

  alias ExLS.LanguageServer.SourceFile

  def definition(text, line, character) do
    case ElixirSense.definition(text, line + 1, character + 1) do
      {"non_existing", nil} -> []
      {file, line} ->
        line = line || 0
        uri = SourceFile.path_to_uri(file)
        %{"uri" => uri, "range" => %{"start" => %{"line" => line - 1, "character" => 0},
          "end" => %{"line" => line - 1, "character" => 0}}}
    end
  end

end
