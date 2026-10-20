# content/templates/

The only part of `content/` that is in the repository. Everything else in `content/` (the
posts, the training plan, private notes) is the author's writing: it lives on the server and is
never committed. These files show what that writing looks like, so a fresh copy of the code can
be given content of its own.

`content/` is an [Obsidian](https://obsidian.md) vault: a folder of markdown files that Obsidian
edits and the site reads directly, every time a page is asked for. Obsidian's "insert template"
command uses this folder.

| Template | Makes | Goes in |
|---|---|---|
| [`blog-template.md`](blog-template.md) | A blog post: the frontmatter block (title, description, date, keywords, `draft: true`) and an empty body | `content/blog/<slug>.md`. The filename is the post's address |
| [`fitness-module-template.md`](fitness-module-template.md) | A training module: a reusable block of exercises that days are assembled from | `content/fitness/modules/` |
| [`fitness-weekly-template.md`](fitness-weekly-template.md) | One day of the week's plan, listing its modules and its one-word theme | `content/fitness/weekly/<day>.md` |

The admin's "New post" button starts from the same blog template, so a post begun in the browser
and one begun in Obsidian look the same.

For a working example of each kind of file, see the invented sample content the tests use, in
`test/support/fixtures/` (`blog/`, `fitness/`). [`docs/how-to.md`](../../docs/how-to.md) Part 4
explains writing a post from start to finish.
