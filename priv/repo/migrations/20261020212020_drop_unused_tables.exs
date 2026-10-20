defmodule Web.Repo.Migrations.DropUnusedTables do
  use Ecto.Migration

  # Tables from features that left or moved to files on disk, none with a
  # schema or a reader any more: the first database-backed blog (posts are
  # read off disk by `Web.Blog`), and early games, groceries, media and
  # workout tracking. The nightly snapshot before this ran holds their rows.
  def up do
    drop_if_exists table(:post_tags)
    drop_if_exists table(:blog_post_edits)
    drop_if_exists table(:tags)
    drop_if_exists table(:blog_posts)
    drop_if_exists table(:games)
    drop_if_exists table(:grocery_items)
    drop_if_exists table(:media_items)
    drop_if_exists table(:workout_sets)
    drop_if_exists table(:workout_sessions)
  end

  def down do
    raise Ecto.MigrationError,
      message: "these tables were unread when dropped; restore rows from a snapshot"
  end
end
