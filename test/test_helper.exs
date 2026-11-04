# Log output is shown only for a test that fails, beside its failure.
# Exports need Pandoc (Web.Writing.Export); where it is not installed (CI),
# the tests that run it are left out.
exclude = if System.find_executable("pandoc"), do: [], else: [:pandoc]
ExUnit.start(capture_log: true, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Web.Repo, :manual)
