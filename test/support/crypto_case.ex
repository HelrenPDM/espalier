defmodule Espalier.CryptoCase do
  @moduledoc """
  Test case for the encryption tests.

  Its setup runs the sandbox setup of `Espalier.DataCase` and then creates the
  temporary table `crypto_samples` inside the sandbox transaction, so the
  table disappears after each test and needs no migration.

  `with_vault_keys/2` restarts `Espalier.Vault` with other keys. Test modules
  that call it, read the vault state or attach telemetry handlers set
  `async: false`.
  """

  use ExUnit.CaseTemplate

  alias Espalier.Repo

  using do
    quote do
      alias Espalier.Repo
      alias Espalier.Test.{CryptoSample, CryptoSampleRotation}

      import Ecto.Query
      import Espalier.CryptoCase
    end
  end

  setup tags do
    Espalier.DataCase.setup_sandbox(tags)

    Repo.query!("""
    CREATE TEMP TABLE crypto_samples (
      id uuid PRIMARY KEY, email bytea, email_hash bytea, profile bytea, secret bytea,
      status text, inserted_at timestamp(0) NOT NULL, updated_at timestamp(0) NOT NULL)
    """)

    Repo.query!(
      "CREATE UNIQUE INDEX crypto_samples_email_hash_index ON crypto_samples (email_hash)"
    )

    :ok
  end

  @doc """
  Runs `fun` while `Espalier.Vault` holds the keys `entries`
  (`[{version, base64}]`), and restores the previous keys afterwards.
  """
  def with_vault_keys(entries, fun) do
    previous = Application.fetch_env!(:espalier, Espalier.Vault)
    Application.put_env(:espalier, Espalier.Vault, Keyword.put(previous, :keys, entries))
    restart_vault!()

    try do
      fun.()
    after
      Application.put_env(:espalier, Espalier.Vault, previous)
      restart_vault!()
    end
  end

  @doc "Returns the raw value of `column` of the row `id` of `crypto_samples`."
  def raw_column(column, id) when column in ~w(email email_hash profile secret) do
    %{rows: [[value]]} =
      Repo.query!("SELECT #{column} FROM crypto_samples WHERE id = $1", [Ecto.UUID.dump!(id)])

    value
  end

  @doc "Writes `value` into `column` of the row `id` of `crypto_samples`."
  def put_raw_column(column, id, value) when column in ~w(email email_hash profile secret) do
    Repo.query!("UPDATE crypto_samples SET #{column} = $1 WHERE id = $2", [
      value,
      Ecto.UUID.dump!(id)
    ])
  end

  @doc "Returns `binary` with the lowest bit of the byte at `index` flipped."
  def flip_bit(binary, index) do
    <<head::binary-size(^index), byte, rest::binary>> = binary
    head <> <<Bitwise.bxor(byte, 1)>> <> rest
  end

  defp restart_vault! do
    :ok = Supervisor.terminate_child(Espalier.Supervisor, Espalier.Vault)
    {:ok, _pid} = Supervisor.restart_child(Espalier.Supervisor, Espalier.Vault)
  end
end
