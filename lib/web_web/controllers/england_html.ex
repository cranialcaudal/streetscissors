defmodule WebWeb.EnglandHTML do
  @moduledoc """
  The templates for the England trip pages (`/england2026`), which are unlisted.
  The templates themselves are the files in `england_html/`; `embed_templates`
  turns each into a function of this module. The trip's facts come from
  `content/england2026/`, never from code (`WebWeb.EnglandController`).
  """

  use WebWeb, :html

  embed_templates "england_html/*"
end
