# docs/

**The documents about the site, written for people.** Start with whichever matches what you
want to do:

| Document | Read it to… | Length |
|---|---|---|
| [`setup.md`](setup.md) | **Install everything and get the site running** on your own machine, step by step | Short |
| [`how-to.md`](how-to.md) | **Understand the whole site**: what it is for, how a roll of film or a markdown file becomes a page, how the machine runs it, how it is backed up. Parts 1–4 assume nothing; Parts 5 onward are for someone running it. Also published at [/how-to](https://streetscissors.com/how-to) | Long |
| [`roadmap.md`](roadmap.md) | See what is built and what comes next. Also published at [/roadmap](https://streetscissors.com/roadmap) | Medium |
| [`negatives-pipeline.md`](negatives-pipeline.md) | Go deep on the film pipeline: the scanner's geometry, the colour maths, how a frame is circled on the contact sheet, and (§9) how `film-develop` learned to read strips scanned on bare glass | Long, technical |
| [`colour/research.md`](colour/research.md) | Read the research behind measured colour from film: what the literature and other tools do | Technical |
| [`colour/contracts.md`](colour/contracts.md) | See the promises each colour stage must keep, and how they are tested | Technical |

The folder READMEs (`lib/README.md`, `tools/README.md` and the others) explain the code folder
by folder, and [`CLAUDE.md`](../CLAUDE.md) at the top lists the rules and traps for anyone
changing code.

## Two documents are live pages

`how-to.md` and `roadmap.md` are read by the running site straight from this folder: **saving
the file changes the page at once**, with no deploy. So:

- They are **public**. Never write a host address, a person's name, anything about the
  unlisted pages, or a security weakness that is still open.
- Save by writing a new file beside the old one and renaming it over, so a reader never gets
  half a file. (Most editors already do this.)
- `how-to.md` is tested: it must keep at least eight parts, a table, and a heading containing
  "keywords". Its headings are also in the site's search. A table's first column never wraps on
  the page, so keep it to a short name.
