defmodule WebWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use WebWeb, :html

  embed_templates "page_html/*"

  @doc """
  The site's beta number, shown beside the homepage's wordmark. 1.0 was the
  deploy of 2026-10-11, the first with the whole revamp live; the second
  number goes up with each deploy that changes what a visitor sees.
  """
  def beta, do: "1.0"
end
