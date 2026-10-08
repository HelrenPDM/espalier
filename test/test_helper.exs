# Timing and mail tests run on their own: mix test --only timing, and
# make test-integration for the mail tests against Mailpit.
ExUnit.configure(exclude: [:timing, :mail])
# Log lines of a test are printed only when it fails.
ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Espalier.Repo, :manual)
