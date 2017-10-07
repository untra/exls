# defmodule ExLS.LanguageServer.Diagnostic do
#   @moduledoc """
#   Diagnostics using Credo!
#   """
#   require Logger

#   def publishDiagnostics(text when text is_bitstring do
#     uri = SourceFile.path_to_uri(file)
#     %{"uri" => uri, "diagnostics" => diagnostics}
#   end

#   # def definition(text, line, character) do
#   #   case ElixirSense.definition(text, line + 1, character + 1) do
#   #     {"non_existing", nil} -> []
#   #     {file, line} ->
#   #       line = line || 0
#   #       uri = SourceFile.path_to_uri(file)
#   #       diagnostics =
#   #       %{"uri" => uri, "diagnostics" => diagnostics}
#   #   end
#   # end

#   ## Helpers

#   defp highlight_range(_line_text, _line, _character, nil) do
#     nil
#   end

#   defp highlight_range(line_text, line, character, substr) do
#     regex_ranges = Regex.scan(~r/\b#{Regex.escape(substr)}\b/, line_text, capture: :first, return: :index)
#     Enum.find_value regex_ranges, fn
#       [{start, length}] when start <= character and character <= start + length ->
#         %{"start" => %{"line" => line, "character" => start},
#           "end" => %{"line" => line, "character" => start + length}}
#       _ ->
#         nil
#     end
#   end

#   defp contents(%{docs: "No documentation available"}) do
#     []
#   end

#   defp contents(%{docs: markdown}) do
#     markdown
#   end

# end
