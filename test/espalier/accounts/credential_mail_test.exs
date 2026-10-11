defmodule Espalier.Accounts.CredentialMailTest do
  @moduledoc """
  Task 0013, steps 12 and 13: `Espalier.Accounts.MailWorker` with the kinds
  `credential_refresh_due` and `credential_expired` sends a plain-text
  mail that names the qualification title, the new status and
  `valid_until` (or, without it, that the credential has no end date) and
  links to `PUBLIC_URL` followed by
  `/me/credentials/<id>`. The job carries ids only, and the worker reads
  the address from the user row at delivery: a user without an address
  receives no mail, and neither does a credential whose status changed
  again since the move.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures
  import Swoosh.TestAssertions

  alias Espalier.Accounts.{MailWorker, User}
  alias Espalier.Credentials

  setup do
    program = publish_demo!()
    %{basics: qualification!(program, "basics"), user: user_fixture()}
  end

  defp link(credential) do
    String.trim_trailing(Application.fetch_env!(:espalier, :public_url), "/") <>
      "/me/credentials/" <> credential.id
  end

  defp args(kind, credential),
    do: %{kind: kind, user_id: credential.user_id, credential_id: credential.id}

  test "credential_refresh_due sends a plain-text mail with title, status, valid_until and link",
       %{basics: basics, user: user} do
    credential =
      credential_fixture(user, basics,
        status: :refresh_due,
        refresh_due_at: ~U[2027-01-02 03:00:00Z],
        valid_until: ~D[2027-01-31]
      )

    assert :ok = perform_job(MailWorker, args("credential_refresh_due", credential))

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.subject == "Your credential needs a refresher"
      assert email.html_body == nil
      assert email.text_body =~ ~s("AI assistant basics")
      assert email.text_body =~ "a refresher is due"
      assert email.text_body =~ "2027-01-31"
      assert email.text_body =~ "Complete the refresher before the credential expires."
      assert email.text_body =~ link(credential)
      true
    end)
  end

  test "credential_refresh_due without valid_until names no end date and asks for the refresher",
       %{basics: basics, user: user} do
    credential =
      credential_fixture(user, basics,
        status: :refresh_due,
        refresh_due_at: ~U[2027-01-02 03:00:00Z],
        valid_until: nil
      )

    assert :ok = perform_job(MailWorker, args("credential_refresh_due", credential))

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.subject == "Your credential needs a refresher"
      assert email.text_body =~ ~s("AI assistant basics")
      assert email.text_body =~ "a refresher is due"
      assert email.text_body =~ "It has no end date."
      assert email.text_body =~ "Complete the refresher to restore it."
      refute email.text_body =~ "before the credential expires"
      assert email.text_body =~ link(credential)
      true
    end)
  end

  test "credential_expired sends a plain-text mail with title, status, valid_until and link",
       %{basics: basics, user: user} do
    credential =
      credential_fixture(user, basics,
        status: :expired,
        refresh_due_at: ~U[2026-12-02 03:00:00Z],
        valid_until: ~D[2026-12-31]
      )

    assert :ok = perform_job(MailWorker, args("credential_expired", credential))

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.subject == "Your credential has expired"
      assert email.html_body == nil
      assert email.text_body =~ ~s("AI assistant basics")
      assert email.text_body =~ "it has expired"
      assert email.text_body =~ "2026-12-31"
      assert email.text_body =~ link(credential)
      true
    end)
  end

  test "the mail job of a sweep reaches the holder", %{basics: basics, user: user} do
    credential = credential_fixture(user, basics, valid_until: ~D[2027-04-01])

    assert {:ok, %{refresh_due: [_moved]}} = Credentials.sweep(~D[2027-03-20])
    assert [job] = all_enqueued(worker: MailWorker)
    refute Enum.any?(Map.values(job.args), &(&1 == user.email))

    assert :ok = perform_job(MailWorker, job.args)

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.text_body =~ "2027-04-01"
      assert email.text_body =~ link(credential)
      true
    end)
  end

  test "a user without an e-mail address receives no mail", %{basics: basics, user: user} do
    credential =
      credential_fixture(user, basics, status: :refresh_due, valid_until: ~D[2027-01-31])

    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [email: nil, email_hash: nil])

    assert :ok = perform_job(MailWorker, args("credential_refresh_due", credential))
    assert_no_email_sent()
  end

  test "a credential whose status changed since the move receives no mail",
       %{basics: basics, user: user} do
    restored = credential_fixture(user, basics, status: :active, valid_until: ~D[2028-01-31])
    assert :ok = perform_job(MailWorker, args("credential_refresh_due", restored))
    assert :ok = perform_job(MailWorker, args("credential_expired", restored))

    due =
      put_credential!(restored, status: :refresh_due, refresh_due_at: ~U[2027-12-01 03:00:00Z])

    assert :ok = perform_job(MailWorker, args("credential_expired", due))

    revoked = put_credential!(due, status: :revoked)
    assert :ok = perform_job(MailWorker, args("credential_refresh_due", revoked))

    assert_no_email_sent()
  end

  test "a job that names another user than the holder sends no mail", %{
    basics: basics,
    user: user
  } do
    credential =
      credential_fixture(user, basics, status: :refresh_due, valid_until: ~D[2027-01-31])

    other = user_fixture()

    assert :ok =
             perform_job(MailWorker, %{
               kind: "credential_refresh_due",
               user_id: other.id,
               credential_id: credential.id
             })

    assert_no_email_sent()
  end
end
