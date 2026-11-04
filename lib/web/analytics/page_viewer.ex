defmodule Web.Analytics.PageWitness do
  @moduledoc """
  That a visitor (`ip_hash`) once read a page, kept after the hits that showed
  it are pruned (`Web.Analytics.prune/0`). One row per page and visitor, with
  no time, path spelling or user agent, so a post's all-time "witnessed"
  count survives the hits' retention without keeping their detail.

  `page` is a hit's path as a page (`Web.Analytics.page/1`): decoded, without
  its query. Only the blog's addresses are folded here, since only they are
  counted for all time.
  """

  use Ecto.Schema

  schema "page_witnesses" do
    field :page, :string
    field :ip_hash, :string
    timestamps(updated_at: false)
  end
end
