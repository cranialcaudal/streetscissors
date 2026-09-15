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
      # The blog's masthead is "Written Work", so its back link says so — not
      # the site's name, which is already the logo beside it.
      "blog" -> {"/blog", "return to written work"}
      "logs" -> {"/logs", "return to captain's logs"}
      "latent-sensus" -> {"/blog", "return to written work"}
      "sensus" -> {"/blog", "return to written work"}
      "another-blog" -> {"/blog", "return to written work"}
      "reflections" -> {"/blog", "return to written work"}
      "fitness" -> {"/fitness", "return to fitness"}
      "fitness-blog" -> {"/fitness", "return to fitness"}
      "sports-blog" -> {"/blog", "return to written work"}
      _ -> {"/", "return to homepage"}
    end
  end
end
