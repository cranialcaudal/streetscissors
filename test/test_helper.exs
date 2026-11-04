# Log output is shown only for a test that fails, beside its failure.
ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Web.Repo, :manual)
