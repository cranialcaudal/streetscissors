defmodule WebWeb.UnsubscribeHTML do
  @moduledoc """
  The templates for the newsletter's unsubscribe page (`/unsubscribe/:token`):
  the files in `unsubscribe_html/`, rendered by `WebWeb.UnsubscribeController`.
  """

  use WebWeb, :html

  embed_templates "unsubscribe_html/*"
end
