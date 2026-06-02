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
      "latent-sensus" -> {"/blog/latent-sensus", "return to latent sensus"}
      "sensus" -> {"/blog/latent-sensus", "return to latent sensus"}
      "another-blog" -> {"/blog/another-blog", "return to another blog"}
      "reflections" -> {"/blog/another-blog", "return to another blog"}
      "fitness-blog" -> {"/blog/fitness-blog", "return to fitness blog"}
      "sports-blog" -> {"/blog/sports-blog", "return to sports blog"}
      _ -> {"/", "return to homepage"}
    end
  end
end
