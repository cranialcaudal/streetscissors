# Credo, as `mix lint` and CI run it: Credo's own defaults, at their strictest,
# with the few changes below, each for the reason beside it. A check that is
# not named here is as Credo ships it.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        # test/private/ is not in the repository, so it is left out to have
        # this machine and CI read the same files.
        excluded: [~r"/_build/", ~r"/deps/", ~r"test/private/"]
      },
      checks: %{
        extra: [
          # Both are looser than Credo's defaults (2 and 9), which a LiveView
          # callback or a parser passes with one `case` inside a `with`. At
          # the defaults they name 103 and 76 functions; at these, the ones
          # worth taking apart first. Tighten them as those are split.
          {Credo.Check.Refactor.Nesting, max_nesting: 3},
          {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 15},
          # Off in Credo by default, on here because each is a rule this
          # codebase already keeps: no atom made from text that arrives at
          # run time (a test may name a process that way), and no `Mix.env/0`
          # where a release would call it, since a release has no Mix.
          {Credo.Check.Warning.UnsafeToAtom, files: %{excluded: ["test/"]}},
          {Credo.Check.Warning.MixEnv, []}
        ],
        disabled: [
          # Asks for an alias wherever a module is named in full. Naming the
          # module where it is used is how this codebase is written.
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
