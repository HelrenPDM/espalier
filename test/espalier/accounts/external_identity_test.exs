defmodule Espalier.Accounts.ExternalIdentityTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.{ExternalIdentity, Scope}

  test "hash_input/3 joins issuer, tenant id and subject with NUL bytes" do
    assert ExternalIdentity.hash_input("demo", nil, "slot-1") == "demo" <> <<0, 0>> <> "slot-1"

    assert ExternalIdentity.hash_input("iss", "tid", "sub") ==
             "iss" <> <<0>> <> "tid" <> <<0>> <> "sub"
  end

  test "the same subject at two issuers yields two subject_hash values" do
    user = user_fixture()
    a = external_identity_fixture(user, issuer: "https://a.example.org", subject: "same")
    b = external_identity_fixture(user, issuer: "https://b.example.org", subject: "same")

    %{rows: rows} =
      Repo.query!("SELECT subject_hash FROM external_identities WHERE id = ANY($1)", [
        [Ecto.UUID.dump!(a.id), Ecto.UUID.dump!(b.id)]
      ])

    assert [[hash_a], [hash_b]] = rows
    assert hash_a != hash_b
  end

  test "the changeset fills subject_hash and ignores a given one" do
    user = user_fixture()

    changeset =
      ExternalIdentity.changeset(
        %ExternalIdentity{},
        %{
          provider_key: "x",
          issuer: "iss",
          tenant_id: "tid",
          subject: "sub",
          subject_hash: "forged"
        },
        Scope.for_user(user)
      )

    assert Ecto.Changeset.get_change(changeset, :subject_hash) ==
             ExternalIdentity.hash_input("iss", "tid", "sub")

    identity = Repo.insert!(changeset)

    assert Repo.get_by(ExternalIdentity,
             provider_key: "x",
             subject_hash: ExternalIdentity.hash_input("iss", "tid", "sub")
           ).id == identity.id

    refute Repo.get_by(ExternalIdentity, provider_key: "x", subject_hash: "forged")
  end

  test "tenant_id is optional and the subject is stored encrypted" do
    identity = external_identity_fixture(user_fixture(), subject: "secret-subject")
    assert is_nil(identity.tenant_id)

    %{rows: [[subject]]} =
      Repo.query!("SELECT subject FROM external_identities WHERE id = $1", [
        Ecto.UUID.dump!(identity.id)
      ])

    refute subject =~ "secret-subject"
  end
end
