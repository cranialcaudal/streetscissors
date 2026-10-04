# Roadmap

The plan for finishing the streetscissors site: what is already standing, what gets built next, and in what order. Written 2026-09-29 and revised as each phase lands.

## 0. What "finished" means

The site is done when:

- **Every section closes its loop.** Each public section can be created, published, read and discovered, whether from files or from the admin.
- **Nothing is half-exposed.** There are no dead routes, and no admin screens that only half work.
- **The machine looks after itself.** Backups, monitoring and deploys run without anyone remembering to do them.
- **A stranger can find the work** through search and feeds.

The file-on-disk model stays the source of truth throughout: every admin tool writes the same files that would otherwise be written by hand in the vault.

## 1. Where it stands

Most of the foundation is already built.

- **Writing.** The blog is markdown on disk, with frontmatter, keywords, reading time and photo and ride embeds. The keywords filter both the blog and the captain's logs, and both sort by most recent or most witnessed.
- **Captain's logs.** They are recorded in the browser, transcoded on the server into one progressive file, and served straight off disk.
- **Negatives.** The archive has a sheet view, an index, a frame view and grease-pencil marks.
- **Fitness.** The regimen and its exercise wiki are read from the vault, and the activities page mirrors every recorded Komoot tour every hour.
- **Correspondence.** The guestbook holds each signature until it is approved. The guestbook and contact forms are rate-limited and carry a captcha. The newsletter sends as durable background jobs, with one-click unsubscribe.
- **Discovery.** There are an RSS feed, a sitemap, a robots file, and a description, canonical URL and share image on every page. AI scrapers are turned away at the proxy.
- **Plumbing.** The database is snapshotted every night and each snapshot is verified. The written content is archived the same night, kept as versions, and each archive is proven by restoring it. Snapshots, versions, the negatives and the recordings are mirrored to an external drive whenever it is plugged in. Deploys are one script with a health gate.
- **Admin.** One back office in one design, the "composing room". It opens on what is waiting and on the state of the machine: backups, the last Komoot sync, the mail queue. Messages have their own inbox and settings their own page. The newsletter has drafts, a preview and a test send.

## 2. Answered and followed (in progress)

A feed is also how people find you, answer you and keep up. This phase gives the site those things in its own terms: nothing counted, nothing ranked, nothing fed.

- **The almanac.** Every day with work in it has a page, holding the essay, the recording, the roll of film and the ride from that day side by side. Every year has a page too, laid out like a contact sheet, and printing it produces a clean edition of the year. Every piece's date links to its day.
- **Letters.** A reader can write to the author about one particular post, log or frame. A letter is signed and private. It appears beneath the piece only if the writer allowed it and the author chooses to.
- **Follow a thought, not an account.** The feed carries the whole site, and any keyword has a feed of its own that follows it across the blog and the logs. The captain's logs arrive in a podcast app as a show.
- **Readable by other sites.** Posts, logs and frames carry the standard IndieWeb markup, so readers and other personal sites understand them without a platform in between. Links to profiles elsewhere are the owner's choice, and there are none by default.
- **Cited by.** When another site links to a piece and says so by webmention, the link is checked. Once the author approves it, it appears beneath the piece.

## 3. Written content joins the nightly backup (done)

The vault was the one thing on the site that could not be rebuilt from somewhere else, and it had no copy. Now:

- Every night the vault, and the few private files that live beside the code, are packed into one archive, which is unpacked again and compared file by file before it counts.
- An archive is kept only when something changed, so the thirty that are kept are thirty versions rather than thirty nights.
- Each version is copied to the external drive when it is plugged in, and so are the captain's logs' recordings, which had no second copy either.
- The admin overview says when the content was last checked and how many versions are kept.

## 4. Publishing loop

- **Blog editor.** Edit a post's source in the admin with a live preview. Saving refuses to overwrite a file that changed on disk since it was opened, so an edit made in Obsidian meanwhile is never lost.
- **Drafts.** A `draft: true` line in a post's frontmatter keeps it off the site and lists it in the admin. Logs already have this through their published switch.
- **Content health.** A report covering:
  - broken internal links;
  - images and embeds that point at nothing;
  - posts missing a description or keywords;
  - files on disk that nothing links to.
- **Keyword tools.** Rename or merge a keyword across the blog and the logs in one action, and list the keywords used only once.
- **Matching templates.** The admin's forms produce the same frontmatter as the Obsidian templates.
- **Archive health for the negatives.** The negatives are made by the film pipeline's own tools, whether they are run from the terminal or from the admin's Scanner page, so this part of the admin reports rather than repairs. It will list which rolls have their grease-pencil marks withheld, the reason (a stale analysis or a sheet whose size doesn't match), and the command that fixes each one.

## 5. Public reading

- **Index parity.** The blog and the logs behave alike: newest first, most witnessed, and keyword filters.
- **Cross-links.** A post can gather related frames, and a log can point at the post it belongs with, without hand-written HTML. (Every piece already links to its day.)
- **Reading polish.**
  - A 404 page that suggests nearby work instead of only a way home.
  - Print styles for the essays.
  - The year as a book: the year's essays and frames as an EPUB or PDF, beside the printable year page.
- **Route audit:** done. Every live page is either linked from somewhere or deliberately unlisted. The kitchen and the finished England trip are unlisted, and the calendar reference moved behind the admin.

## 6. Discovery

- **Homepage.** Decide the homepage's title, description and visible name text, then implement them.
- **Search engines.** Claim Search Console and Bing Webmaster Tools, submit the sitemap, and follow index coverage until the homepage and the key pages appear for the site's name.
- **Share images.** Every post, frame and log gets its own share image, so a shared link unfurls with the work itself rather than the site default.
- **Sending webmentions.** When a post links to another personal site, tell that site, so a citation runs both ways.

## 7. Fitness

- The exercise wiki keeps growing, one entry per new movement.
- The regimen's modules and the week plan become editable from the admin, like the wiki already is.

## 8. Correspondence

- **Guestbook:** done. A new signature is mailed to the author with its words and a link to approve it.
- **Newsletter** (optional). Open and click counts, self-hosted through the site's own redirect, with no third-party tracker.

## 9. Plumbing

The self-hosting is the point, so the plumbing should be boring and automatic.

- **Monitoring:** done.
  - Every fifteen minutes the machine checks its certificate, its proxy, where the domain points, its disk and its services, along with the backups.
  - A fault is mailed to the author once it has failed twice running, again each day it lasts, and once more when it clears.
  - `/health` answers whether the proxy, the application and the database are all standing, and a scheduled job on GitHub asks it from outside, since nothing on the machine can report the machine being off.
  - The domain's address is checked against the machine's own. The registrar offers no way to update it automatically, so a change is mailed with the new value to enter.
- **Restores.** Restore a snapshot onto a scratch copy on a schedule, to prove the backups work.
- **Rollback.** Document how to return to the previous release in one command, and try it once.
- **Dependencies.** Upgrade the framework and libraries on a schedule rather than when something breaks.
- **Images.** Serve sized copies of photographs everywhere a full scan isn't needed.

## 10. Cleanup

- **The content folder:** done. Private notes and drafts have folders of their own, so the root holds only what the site reads.
- **Old notes.** Retire the old architecture notes once the how-to covers the same ground.

## 11. Sequencing

- **Phase 1, the admin:** done.
- **Phase 2, answered and followed:** the almanac, letters, feeds, IndieWeb markup, and webmentions received.
- **Phase 3, the backup:** done.
- **Phase 4, the publishing loop:** the blog editor, drafts, content health, and keyword tools.
- **Phase 5, public polish:** index parity, cross-links, the 404 page, print styles, the year as a book, and the route audit.
- **Phase 6, discovery:** the homepage decision, search engines, share images, and sending webmentions.
- **Phase 7, plumbing:** monitoring, restore tests, rollback, and dependency upgrades.
- **Phase 8, the rest:** fitness editing, correspondence, image sizes, and cleanup.

Each phase ends with a redeploy and a live check of what changed.
