defmodule WebWeb.Navigation do
  @moduledoc """
  Shared "where did the reader come from" helper.

  Pages accept a `?from=` query param identifying the originating portal and
  render a back link to it. This is the single source of truth for the
  `from -> {return_to, return_label}` mapping; controllers and LiveViews call
  `return_context/1` rather than each carrying their own copy (which had drifted
  out of sync).
  """

  @doc """
  Maps a `from` token to `{return_to, return_label}` for the back link.

  Falls back to the homepage for unknown or missing tokens.
  """
  @spec return_context(String.t() | nil) :: {String.t(), String.t()}
  def return_context(from) do
    case from do
      "blog" -> {"/blog", "return to streetscissors"}
      "logs" -> {"/logs", "return to captain's logs"}
      "latent-sensus" -> {"/blog", "return to streetscissors"}
      "sensus" -> {"/blog", "return to streetscissors"}
      "another-blog" -> {"/blog", "return to streetscissors"}
      "reflections" -> {"/blog", "return to streetscissors"}
      "fitness" -> {"/fitness", "return to fitness"}
      "fitness-blog" -> {"/fitness", "return to fitness"}
      "sports-blog" -> {"/blog", "return to streetscissors"}
      _ -> {"/", "return to homepage"}
    end
  end
end
