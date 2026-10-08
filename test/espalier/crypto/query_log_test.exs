defmodule Espalier.Crypto.QueryLogTest do
  # Attaches telemetry handlers and changes the Logger level.
  use Espalier.CryptoCase, async: false

  import ExUnit.CaptureLog

  alias Espalier.Telemetry.QueryLog

  @event [:espalier, :repo, :query]

  setup do
    canary = "canary-#{System.unique_integer([:positive])}@example.org"
    handler_id = "test-query-log-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler_id, @event, &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
    %{canary: canary}
  end

  def forward(_event, measurements, metadata, test_pid) do
    send(test_pid, {:query, measurements, metadata})
  end

  test "production turns the Repo log off and the query log on" do
    config = Config.Reader.read!("config/prod.exs", env: :prod)
    assert config[:espalier][Espalier.Repo][:log] == false
    assert config[:espalier][QueryLog][:enabled] == true
  end

  test "scrub/1 and format/2 drop the plaintext that the metadata carries", %{canary: canary} do
    insert_sample(canary)

    assert_receive {:query, measurements, %{query: "INSERT" <> _} = metadata}

    # The logging hazard on the pinned toolchain: the cast parameters hold
    # the plaintext of the encrypted and the hashed field.
    assert canary in metadata.cast_params

    refute inspect(QueryLog.scrub(metadata), limit: :infinity) =~ canary
    line = QueryLog.format(measurements, metadata)
    refute line =~ canary
    assert line =~ ~r/\AQUERY INSERT source=crypto_samples total=\d+\.\dms\z/
  end

  test "a lookup by keyed hash carries the plaintext only in the parameters", %{canary: canary} do
    insert_sample(canary)
    assert_receive {:query, _measurements, %{query: "INSERT" <> _}}

    Repo.get_by(CryptoSample, email_hash: canary)
    assert_receive {:query, measurements, %{query: "SELECT" <> _} = metadata}
    assert canary in metadata.cast_params
    refute inspect(QueryLog.scrub(metadata), limit: :infinity) =~ canary
    refute QueryLog.format(measurements, metadata) =~ canary
  end

  # The test Repo keeps the query log of ecto_sql, which prints the canary in
  # its own lines; config/prod.exs turns that log off (first test above).
  test "the attached handler logs queries without the plaintext", %{canary: canary} do
    level = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      :telemetry.detach("espalier-query-log")
      Logger.configure(level: level)
    end)

    assert :ok = QueryLog.attach()

    log = capture_log([level: :debug], fn -> insert_sample(canary) end)
    assert log =~ canary

    assert [line] =
             log
             |> String.split("\n")
             |> Enum.filter(&(&1 =~ "QUERY INSERT source=crypto_samples"))

    refute line =~ canary
  end

  test "only the query log and test handlers listen to Repo queries" do
    for %{id: id} <- :telemetry.list_handlers(@event) do
      assert id == "espalier-query-log" or String.starts_with?(id, "test-"), inspect(id)
    end
  end

  defp insert_sample(email) do
    %CryptoSample{}
    |> CryptoSample.changeset(%{email: email, secret: email})
    |> Repo.insert!()
  end
end
