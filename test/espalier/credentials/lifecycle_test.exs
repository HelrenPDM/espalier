defmodule Espalier.Credentials.LifecycleTest do
  @moduledoc """
  Task 0013, step 24, bullet "Sweep" (steps 12 and 13): the notice and
  grace boundaries of `Espalier.Credentials.sweep/1` with explicit dates
  and with the settings `CREDENTIAL_NOTICE_DAYS` and
  `CREDENTIAL_GRACE_DAYS`, a credential without `valid_until`, one state
  per sweep, the mail job with ids only and one webhook job per subscribed
  active webhook for each transition, revoked credentials,
  `Espalier.Credentials.SweepWorker` and `mark_refresh_due_for_policy/1`.
  """
  # Application.put_env/3 changes the notice and grace days for the node.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.MailWorker
  alias Espalier.Credentials
  alias Espalier.Credentials.{Credential, SweepWorker, WebhookWorker}

  @today ~D[2027-03-15]
  @earlier ~U[2027-01-10 09:00:00Z]

  setup do
    program = publish_demo!()

    %{
      program: program,
      basics: qualification!(program, "basics"),
      workshop: qualification!(program, "workshop")
    }
  end

  defp put_env!(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end

  defp notice_days, do: Application.get_env(:espalier, :credential_notice_days, 30)
  defp grace_days, do: Application.get_env(:espalier, :credential_grace_days, 30)

  # A credential of a new user, so that one test can hold several
  # credentials for one qualification.
  defp credential!(qualification, attrs),
    do: credential_fixture(user_fixture(), qualification, attrs)

  defp refresh_due!(qualification, valid_until) do
    credential!(qualification,
      status: :refresh_due,
      refresh_due_at: @earlier,
      valid_until: valid_until
    )
  end

  defp reload(credential), do: Repo.get!(Credential, credential.id)

  defp ids(credentials), do: credentials |> Enum.map(& &1.id) |> Enum.sort()

  defp mail_jobs, do: all_enqueued(worker: MailWorker)
  defp webhook_jobs, do: all_enqueued(worker: WebhookWorker)

  defp recent?(%DateTime{} = at), do: abs(DateTime.diff(DateTime.utc_now(), at)) <= 5

  defp no_address?(args) do
    not Enum.any?(Map.values(args), &(is_binary(&1) and String.contains?(&1, "@")))
  end

  describe "sweep/1 with explicit dates" do
    test "moves an active credential whose valid_until minus the notice days is today, not one day later",
         %{basics: basics} do
      on_boundary = credential!(basics, valid_until: Date.add(@today, notice_days()))
      one_day_later = credential!(basics, valid_until: Date.add(@today, notice_days() + 1))

      assert {:ok, %{refresh_due: [moved], expired: []}} = Credentials.sweep(@today)
      assert moved.id == on_boundary.id

      on_boundary = reload(on_boundary)
      assert on_boundary.status == :refresh_due
      assert recent?(on_boundary.refresh_due_at)

      one_day_later = reload(one_day_later)
      assert one_day_later.status == :active
      assert one_day_later.refresh_due_at == nil
    end

    test "expires a refresh_due credential whose valid_until plus the grace days lies before today, not on today",
         %{basics: basics} do
      before_today = refresh_due!(basics, Date.add(@today, -(grace_days() + 1)))
      on_today = refresh_due!(basics, Date.add(@today, -grace_days()))

      assert {:ok, %{refresh_due: [], expired: [moved]}} = Credentials.sweep(@today)
      assert moved.id == before_today.id

      before_today = reload(before_today)
      assert before_today.status == :expired
      assert before_today.refresh_due_at == @earlier

      assert reload(on_today).status == :refresh_due
    end

    test "reads the notice and grace days from the settings", %{basics: basics} do
      put_env!(:credential_notice_days, 7)
      put_env!(:credential_grace_days, 3)

      notice_today = credential!(basics, valid_until: Date.add(@today, 7))
      notice_later = credential!(basics, valid_until: Date.add(@today, 8))
      grace_before = refresh_due!(basics, Date.add(@today, -4))
      grace_today = refresh_due!(basics, Date.add(@today, -3))

      assert {:ok, %{refresh_due: refresh_due, expired: expired}} = Credentials.sweep(@today)
      assert ids(refresh_due) == [notice_today.id]
      assert ids(expired) == [grace_before.id]

      assert reload(notice_today).status == :refresh_due
      assert reload(notice_later).status == :active
      assert reload(grace_before).status == :expired
      assert reload(grace_today).status == :refresh_due
    end

    test "leaves a credential without valid_until active", %{workshop: workshop} do
      credential = credential!(workshop, valid_until: nil)

      assert {:ok, %{refresh_due: [], expired: []}} = Credentials.sweep(@today)
      assert {:ok, %{refresh_due: [], expired: []}} = Credentials.sweep(Date.add(@today, 5_000))

      assert reload(credential).status == :active
      assert mail_jobs() == []
      assert webhook_jobs() == []
    end

    test "moves a credential by one state per sweep", %{basics: basics} do
      credential = credential!(basics, valid_until: Date.add(@today, -400))

      assert {:ok, %{refresh_due: [_moved], expired: []}} = Credentials.sweep(@today)
      assert reload(credential).status == :refresh_due
      assert Enum.map(mail_jobs(), & &1.args["kind"]) == ["credential_refresh_due"]

      assert {:ok, %{refresh_due: [], expired: [_moved]}} = Credentials.sweep(@today)
      assert reload(credential).status == :expired

      assert mail_jobs() |> Enum.map(& &1.args["kind"]) |> Enum.sort() ==
               ["credential_expired", "credential_refresh_due"]
    end

    test "each transition enqueues one mail job with ids only and one webhook job per subscribed active webhook",
         %{basics: basics} do
      lifecycle = webhook_fixture(events: ["credential.refresh_due", "credential.expired"])
      every_event = webhook_fixture()
      _inactive = webhook_fixture(active: false)
      _unsubscribed = webhook_fixture(events: ["credential.issued", "credential.revoked"])

      due = credential!(basics, valid_until: Date.add(@today, 1))
      expiring = refresh_due!(basics, Date.add(@today, -400))

      assert {:ok, %{refresh_due: [_due], expired: [_expired]}} = Credentials.sweep(@today)

      mails = mail_jobs()
      assert length(mails) == 2

      for job <- mails do
        assert job.queue == "mail"
        assert job.args |> Map.keys() |> Enum.sort() == ["credential_id", "kind", "user_id"]
        assert no_address?(job.args)
      end

      assert Enum.sort(for job <- mails, do: {job.args["credential_id"], job.args["kind"]}) ==
               Enum.sort([
                 {due.id, "credential_refresh_due"},
                 {expiring.id, "credential_expired"}
               ])

      for job <- mails do
        credential = if job.args["credential_id"] == due.id, do: due, else: expiring
        assert job.args["user_id"] == credential.user_id
      end

      hooks = webhook_jobs()

      for job <- hooks do
        assert job.args |> Map.keys() |> Enum.sort() ==
                 ["credential_id", "event", "occurred_at", "webhook_id"]

        assert no_address?(job.args)
      end

      assert Enum.sort(
               for job <- hooks,
                   do: {job.args["credential_id"], job.args["event"], job.args["webhook_id"]}
             ) ==
               Enum.sort([
                 {due.id, "credential.refresh_due", lifecycle.id},
                 {due.id, "credential.refresh_due", every_event.id},
                 {expiring.id, "credential.expired", lifecycle.id},
                 {expiring.id, "credential.expired", every_event.id}
               ])
    end

    test "leaves revoked credentials untouched and enqueues nothing for them", %{basics: basics} do
      _webhook = webhook_fixture()
      past_notice = credential!(basics, status: :revoked, valid_until: Date.add(@today, -400))

      past_grace =
        credential!(basics,
          status: :revoked,
          refresh_due_at: @earlier,
          valid_until: Date.add(@today, -400)
        )

      assert {:ok, %{refresh_due: [], expired: []}} = Credentials.sweep(@today)
      assert {:ok, []} = Credentials.mark_refresh_due_for_policy("usage-policy")

      assert reload(past_notice).status == :revoked
      assert reload(past_notice).refresh_due_at == nil
      assert reload(past_grace).status == :revoked
      assert mail_jobs() == []
      assert webhook_jobs() == []
    end
  end

  test "SweepWorker sweeps on today's date", %{basics: basics} do
    today = Date.utc_today()
    due = credential!(basics, valid_until: Date.add(today, notice_days()))
    not_due = credential!(basics, valid_until: Date.add(today, notice_days() + 1))
    expiring = refresh_due!(basics, Date.add(today, -(grace_days() + 1)))
    in_grace = refresh_due!(basics, Date.add(today, -grace_days()))

    assert :ok = perform_job(SweepWorker, %{})

    assert reload(due).status == :refresh_due
    assert reload(not_due).status == :active
    assert reload(expiring).status == :expired
    assert reload(in_grace).status == :refresh_due
    assert length(mail_jobs()) == 2
  end

  test "SweepWorker runs in the default queue" do
    assert get_field(SweepWorker.new(%{}), :queue) == "default"
  end

  describe "mark_refresh_due_for_policy/1" do
    test "moves the active credentials of the policy and enqueues the mail and credential.refresh_due",
         %{basics: basics, workshop: workshop} do
      webhook = webhook_fixture(events: ["credential.refresh_due"])
      _issued_only = webhook_fixture(events: ["credential.issued"])

      active = credential!(basics, valid_until: Date.add(Date.utc_today(), 300))
      already_due = refresh_due!(basics, Date.add(Date.utc_today(), 10))
      other_qualification = credential!(workshop, valid_until: nil)

      assert Credentials.count_affected_by_policy("usage-policy") == 1
      assert {:ok, [moved]} = Credentials.mark_refresh_due_for_policy("usage-policy")
      assert moved.id == active.id

      active = reload(active)
      assert active.status == :refresh_due
      assert recent?(active.refresh_due_at)
      assert reload(already_due).refresh_due_at == @earlier
      assert reload(other_qualification).status == :active

      assert [mail] = mail_jobs()

      assert mail.args == %{
               "kind" => "credential_refresh_due",
               "user_id" => active.user_id,
               "credential_id" => active.id
             }

      assert [hook] = webhook_jobs()
      assert hook.args["event"] == "credential.refresh_due"
      assert hook.args["credential_id"] == active.id
      assert hook.args["webhook_id"] == webhook.id
      assert no_address?(hook.args)

      assert Credentials.count_affected_by_policy("usage-policy") == 0
    end

    test "moves nothing for a policy that no requirement names", %{basics: basics} do
      credential = credential!(basics, valid_until: nil)

      assert Credentials.count_affected_by_policy("another-policy") == 0
      assert {:ok, []} = Credentials.mark_refresh_due_for_policy("another-policy")
      assert reload(credential).status == :active
      assert mail_jobs() == []
    end
  end
end
