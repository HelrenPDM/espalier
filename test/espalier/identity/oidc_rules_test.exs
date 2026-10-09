defmodule Espalier.Identity.OidcRulesTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Identity.{Assertion, Claims, OidcProvider}
  alias Espalier.Identity.Oidc.Rules

  @tenant "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d"

  @entra %OidcProvider{
    key: "entra",
    type: "entra",
    issuer: "https://login.microsoftonline.com/#{@tenant}/v2.0",
    tenant_id: @tenant,
    role_claim: "roles",
    role_map: [author: "Espalier.Author", admin: "Espalier.Admin"]
  }
  @google %OidcProvider{
    key: "google",
    type: "google",
    issuer: "https://accounts.google.com",
    hosted_domain: "example.org"
  }
  @oidc %OidcProvider{
    key: "corp",
    type: "oidc",
    issuer: "https://id.example.org",
    role_claim: "groups",
    role_map: [admin: "platform-admins"]
  }

  @sign_in %{"purpose" => "sign_in", "requested_at" => 1_000}

  # A compact token whose protected header carries `alg`; Rules.check/4 runs
  # after oidcc has validated the signature, so the signature is not checked.
  defp token(alg \\ "RS256") do
    encode = &Base.url_encode64(&1, padding: false)
    encode.(JSON.encode!(%{"alg" => alg})) <> "." <> encode.("{}") <> ".sig"
  end

  defp entra_claims(extra \\ %{}) do
    Map.merge(
      %{"sub" => "pairwise", "oid" => "object-id", "tid" => String.upcase(@tenant)},
      extra
    )
  end

  test "the protected header must name RS256, PS256 or ES256" do
    for alg <- ["RS256", "PS256", "ES256"] do
      assert {:ok, _} = Rules.check(@oidc, token(alg), %{"sub" => "s"}, @sign_in)
    end

    for alg <- ["HS256", "none", "RS512"] do
      assert Rules.check(@oidc, token(alg), %{"sub" => "s"}, @sign_in) ==
               {:error, :alg_not_allowed}
    end

    assert Rules.check(@oidc, "not-a-token", %{"sub" => "s"}, @sign_in) ==
             {:error, :alg_not_allowed}
  end

  describe "entra" do
    test "keys the identity by tid and oid" do
      assert {:ok, %Assertion{subject: "object-id", tenant_id: @tenant, issuer: issuer}} =
               Rules.check(@entra, token(), entra_claims(), @sign_in)

      assert issuer == @entra.issuer
    end

    test "a tenant mismatch, a missing oid and the groups overage fail" do
      assert Rules.check(@entra, token(), entra_claims(%{"tid" => "other"}), @sign_in) ==
               {:error, :tenant_mismatch}

      assert Rules.check(@entra, token(), Map.delete(entra_claims(), "oid"), @sign_in) ==
               {:error, :missing_claim}

      overage = entra_claims(%{"_claim_names" => %{"groups" => "src1"}})
      assert Rules.check(@entra, token(), overage, @sign_in) == {:error, :groups_overage}

      assert Rules.check(@entra, token(), entra_claims(%{"hasgroups" => true}), @sign_in) ==
               {:error, :groups_overage}
    end

    test "reads roles and maps them" do
      claims = entra_claims(%{"roles" => ["Espalier.Author", "Other"]})
      {:ok, assertion} = Rules.check(@entra, token(), claims, @sign_in)
      assert assertion.roles == ["Espalier.Author", "Other"]
      assert Claims.map_roles(assertion.roles, @entra.role_map) == [:author]

      {:ok, assertion} = Rules.check(@entra, token(), entra_claims(%{"roles" => "x"}), @sign_in)
      assert assertion.roles == []
    end

    test "e-mail: xms_edov counts, preferred_username and upn never" do
      claims = entra_claims(%{"email" => "ada@example.org", "xms_edov" => true})
      assert {:ok, %{email: "ada@example.org"}} = Rules.check(@entra, token(), claims, @sign_in)

      claims =
        entra_claims(%{
          "email" => "ada@example.org",
          "preferred_username" => "ada@example.org",
          "upn" => "ada@example.org"
        })

      assert {:ok, %{email: nil}} = Rules.check(@entra, token(), claims, @sign_in)
    end
  end

  describe "google and generic OIDC" do
    test "hd must equal the hosted domain, and sub keys the identity" do
      claims = %{"sub" => "g-1", "hd" => "EXAMPLE.org"}

      assert {:ok, %{subject: "g-1", tenant_id: nil, roles: []}} =
               Rules.check(@google, token(), claims, @sign_in)

      assert Rules.check(@google, token(), %{"sub" => "g-1", "hd" => "example.net"}, @sign_in) ==
               {:error, :domain_mismatch}

      assert Rules.check(@google, token(), %{"sub" => "g-1"}, @sign_in) ==
               {:error, :domain_mismatch}
    end

    test "e-mail only when verified" do
      verified = %{"sub" => "g", "hd" => "example.org", "email" => "g@example.org"}

      assert {:ok, %{email: "g@example.org"}} =
               Rules.check(@google, token(), Map.put(verified, "email_verified", true), @sign_in)

      assert {:ok, %{email: nil}} =
               Rules.check(@google, token(), Map.put(verified, "email_verified", false), @sign_in)

      assert {:ok, %{email: nil}} = Rules.check(@google, token(), verified, @sign_in)
    end

    test "roles come from the role claim, and a distributed role claim fails" do
      {:ok, assertion} =
        Rules.check(@oidc, token(), %{"sub" => "o", "groups" => ["platform-admins"]}, @sign_in)

      assert Claims.map_roles(assertion.roles, @oidc.role_map) == [:admin]

      claims = %{"sub" => "o", "_claim_names" => %{"groups" => "src1"}}
      assert Rules.check(@oidc, token(), claims, @sign_in) == {:error, :distributed_role_claim}
    end

    test "display name, amr and sid" do
      long = String.duplicate("é", 250)

      {:ok, assertion} =
        Rules.check(
          @oidc,
          token(),
          %{"sub" => "o", "name" => "  #{long} ", "amr" => ["pwd", "mfa"], "sid" => "s-1"},
          @sign_in
        )

      assert String.length(assertion.display_name) == 200
      assert assertion.amr == ["pwd", "mfa"]
      assert assertion.sid == "s-1"

      {:ok, assertion} = Rules.check(@oidc, token(), %{"sub" => "o", "amr" => "pwd"}, @sign_in)
      assert assertion.amr == nil
      assert assertion.sid == nil
    end
  end

  test "Claims.map_roles/2 returns each mapped role once" do
    role_map = [author: "a", author: "b", admin: "c"]
    assert Claims.map_roles(["a", "b"], role_map) == [:author]
    assert Claims.map_roles(["c", "x"], role_map) == [:admin]
    assert Claims.map_roles([], role_map) == []
  end

  describe "auth_time at a step-up" do
    test "must be at least requested_at minus 60 seconds" do
      tx = %{"purpose" => "step_up", "requested_at" => 1_000}

      assert {:ok, _} = Rules.check(@oidc, token(), %{"sub" => "o", "auth_time" => 940}, tx)

      assert Rules.check(@oidc, token(), %{"sub" => "o", "auth_time" => 939}, tx) ==
               {:error, :stale_auth_time}

      assert Rules.check(@oidc, token(), %{"sub" => "o"}, tx) == {:error, :stale_auth_time}

      assert Rules.check(@oidc, token(), %{"sub" => "o", "auth_time" => "1000"}, tx) ==
               {:error, :stale_auth_time}

      assert {:ok, _} = Rules.check(@oidc, token(), %{"sub" => "o"}, @sign_in)
    end
  end

  describe "idp_mfa?/2" do
    test "in idp_trusted mode" do
      provider = %{@oidc | mfa: :idp_trusted, mfa_amr: ["mfa"]}

      assert Rules.idp_mfa?(provider, %Assertion{amr: nil})
      refute Rules.idp_mfa?(provider, %Assertion{amr: ["pwd"]})
      assert Rules.idp_mfa?(provider, %Assertion{amr: ["pwd", "mfa"]})

      hwk = %{provider | mfa_amr: ["hwk"]}
      refute Rules.idp_mfa?(hwk, %Assertion{amr: ["pwd", "mfa"]})
      assert Rules.idp_mfa?(hwk, %Assertion{amr: ["hwk"]})
    end

    test "never in local mode" do
      provider = %{@oidc | mfa: :local}

      for amr <- [nil, ["pwd"], ["pwd", "mfa"], ["hwk"]] do
        refute Rules.idp_mfa?(provider, %Assertion{amr: amr})
      end
    end
  end

  test "the same sub at two issuers yields two subject_hash values" do
    user_a = user_fixture()
    user_b = user_fixture()

    a =
      external_identity_fixture(user_a,
        provider_key: "a",
        issuer: "https://a.example.org",
        subject: "sub-1"
      )

    b =
      external_identity_fixture(user_b,
        provider_key: "a",
        issuer: "https://b.example.org",
        subject: "sub-1"
      )

    %{rows: [[hash_a], [hash_b]]} =
      Repo.query!("SELECT subject_hash FROM external_identities WHERE id = ANY($1) ORDER BY id", [
        [Ecto.UUID.dump!(a.id), Ecto.UUID.dump!(b.id)]
      ])

    assert hash_a != hash_b
  end
end
