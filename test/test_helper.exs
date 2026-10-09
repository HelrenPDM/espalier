# Timing, mail and LDAP tests run on their own: mix test --only timing, and
# make test-integration for the mail tests against Mailpit and the LDAP tests
# against lldap.
Mox.defmock(Espalier.Identity.Ldap.ClientMock, for: Espalier.Identity.Ldap.Client)
ExUnit.configure(exclude: [:timing, :mail, :ldap])
# Log lines of a test are printed only when it fails.
ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Espalier.Repo, :manual)
