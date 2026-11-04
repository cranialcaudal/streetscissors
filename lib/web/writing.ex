defmodule Web.Writing do
  @moduledoc """
  The writing workbench's context: where pieces that are not blog posts live, and the shapes a new one can start from.

  The modules under `Web.Writing` know nothing of the blog, so the same
  outline, citations, Zotero and export serve an essay, a paper or a grant:

    * `Web.Writing.Document`: a file's frontmatter, project settings and preview;
    * `Web.Writing.Outline`: reading list, sections, beats and thoughts;
    * `Web.Writing.Citations`: `[@key]` citations and their References;
    * `Web.Writing.Zotero`: the Zotero Web API;
    * `Web.Writing.Export`: Word, PDF and LaTeX through Pandoc;
    * `Web.Writing.Papers`: the folder of pieces that are not posts.

  The folder for papers is `config :web, :writing_path` (`WRITING_PATH`), else
  `writing/` beside the blog folder in the vault, so Obsidian sees it.
  """

  @doc "The folder papers are kept in."
  def papers_path do
    Application.get_env(:web, :writing_path) ||
      Path.join(Path.dirname(Web.Blog.base_path()), "writing")
  end

  @doc """
  The shapes a new piece can start from, as `{kind, label}`: each a skeleton
  of sections with word goals and beats, and an empty reading list.
  """
  def kinds do
    [
      {"essay", "Essay"},
      {"article", "Research article (IMRaD)"},
      {"review", "Literature review"},
      {"aims", "Specific aims page"},
      {"response", "Response to reviewers"}
    ]
  end

  @doc "The body (below the frontmatter) a new piece of `kind` starts with."
  def skeleton(kind)

  def skeleton("article") do
    """
    ## Reading List

    ## Abstract (~250 words)

    > [!beat] Problem, approach, finding, implication
    > One sentence each.

    ## Introduction (~800 words)

    > [!beat] What is known
    > The ground the field agrees on, cited.

    > [!beat] The gap
    > What that leaves unanswered, and why it matters.

    > [!beat] This study
    > The question, the approach, and what it adds.

    ## Methods (~1000 words)

    > [!beat] Participants or materials

    > [!beat] Procedure and measures

    > [!beat] Analysis

    ## Results (~1000 words)

    > [!beat] The main finding

    > [!beat] Secondary findings

    ## Discussion (~1200 words)

    > [!beat] What the finding means
    > Against the gap set out in the introduction.

    > [!beat] Against prior work
    > Where it agrees and where it does not, cited.

    > [!beat] Limitations

    > [!beat] What follows
    """
  end

  def skeleton("review") do
    """
    ## Reading List

    ## Introduction (~600 words)

    > [!beat] Scope
    > The question the review answers, and what is left out.

    > [!beat] How the literature was found
    > Databases, terms, years, and what was kept.

    ## Theme one (~1200 words)

    > [!beat] The claim

    > [!beat] The evidence for it

    > [!beat] Where it is contested

    ## Theme two (~1200 words)

    > [!beat] The claim

    > [!beat] The evidence for it

    > [!beat] Where it is contested

    ## Synthesis and gaps (~800 words)

    > [!beat] What the themes say together

    > [!beat] What no one has studied yet

    ## Conclusion (~300 words)
    """
  end

  def skeleton("aims") do
    """
    ## Reading List

    ## Opening (~150 words)

    > [!beat] The problem and its cost

    > [!beat] What is known, and the gap
    > Cited.

    ## Long-term goal and objective (~120 words)

    > [!beat] Long-term goal

    > [!beat] Objective of this proposal, and the central hypothesis

    ## Aim 1 (~120 words)

    > [!beat] Aim, hypothesis and approach

    ## Aim 2 (~120 words)

    > [!beat] Aim, hypothesis and approach

    ## Expected outcomes and impact (~100 words)
    """
  end

  def skeleton("response") do
    """
    ## Reading List

    ## Summary of changes (~200 words)

    > [!beat] The main changes, in a paragraph

    ## Reviewer 1

    > [!beat] Comment 1.1
    > Quote the comment, answer it, say where the manuscript changed.

    > [!beat] Comment 1.2

    ## Reviewer 2

    > [!beat] Comment 2.1

    > [!beat] Comment 2.2
    """
  end

  def skeleton(_essay) do
    """
    ## Reading List

    ## Introduction (~300 words)

    > [!beat] The hook

    > [!beat] The thesis

    ## The argument (~900 words)

    > [!beat] First move

    > [!beat] Second move

    > [!beat] The strongest objection, answered

    ## Conclusion (~300 words)

    > [!beat] What it changes
    """
  end
end
