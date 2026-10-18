# Timing, mail, LDAP and ClamAV tests run on their own: mix test --only
# timing, and make test-integration for the mail tests against Mailpit, the
# LDAP tests against lldap and the ClamAV tests against clamd of the shell.
Mox.defmock(Espalier.Identity.Ldap.ClientMock, for: Espalier.Identity.Ldap.Client)
ExUnit.configure(exclude: [:timing, :mail, :ldap, :clamav])
# Log lines of a test are printed only when it fails.
ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Espalier.Repo, :manual)
