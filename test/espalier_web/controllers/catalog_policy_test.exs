defmodule EspalierWeb.CatalogPolicyTest do
  @moduledoc """
  The current policy text in the catalog views (task 0013, spec step 21 and
  the bullet "Catalog and configuration" of step 24; README section 7,
  domain rule 8).

  A block of kind `placeholder` in `GET /api/modules/:id` and each
  placeholder of `GET /api/programs/:slug/handbook` carry `policy` with
  `key`, `number`, `effective_from` and `body` of the current version of
  the policy named by the placeholder key, or `null` while that policy has
  no published version. The current version is the published version with
  the highest number; drafts do not count.
  """
  use EspalierWeb.ConnCase, async: true

  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures
  import OpenApiSpex.TestAssertions

  alias Espalier.Accounts.Scope
  alias Espalier.Policies
  alias EspalierWeb.ApiSpec

  setup do
    program = publish_demo!()
    %{program: program, conn: log_in_user(api_conn(), user_fixture()), spec: ApiSpec.spec()}
  end

  defp module_body(conn, program, number) do
    conn
    |> json_request(:get, "/api/modules/#{module!(program, number).id}")
    |> json_response(200)
  end

  defp handbook(conn, program) do
    conn |> json_request(:get, "/api/programs/#{program.slug}/handbook") |> json_response(200)
  end

  defp blocks(body), do: Enum.flat_map(body["lessons"], & &1["blocks"])

  defp placeholder_blocks(body), do: Enum.filter(blocks(body), &(&1["kind"] == "placeholder"))

  defp other_blocks(body), do: Enum.reject(blocks(body), &(&1["kind"] == "placeholder"))

  # Publishes version 2 of input-rules before version 1 and leaves version
  # 3 as a draft, so that only the number decides which version is current.
  defp publish_input_rules! do
    policy = policy_fixture(%{key: "input-rules", title: "Input rules"})
    first = draft_version_fixture(policy, %{body: "First text.", effective_from: ~D[2026-02-01]})

    second =
      draft_version_fixture(policy, %{body: "Second text.", effective_from: ~D[2026-06-01]})

    {:ok, _second} = Policies.publish_version(Scope.system(), second)
    {:ok, _first} = Policies.publish_version(Scope.system(), first)
    draft_version_fixture(policy, %{body: "A draft.", effective_from: ~D[2026-12-01]})

    %{
      "key" => "input-rules",
      "number" => 2,
      "effective_from" => "2026-06-01",
      "body" => "Second text."
    }
  end

  describe "GET /api/modules/:id" do
    test "the placeholder block of module 1 carries policy null without a published version",
         %{conn: conn, program: program, spec: spec} do
      body = module_body(conn, program, 1)
      assert_schema(body, "ModuleView", spec)
      assert [%{"placeholder_key" => "input-rules", "policy" => nil}] = placeholder_blocks(body)

      draft_version_fixture(policy_fixture(%{key: "input-rules"}), %{body: "A draft."})
      published_policy!("usage-policy")

      body = module_body(conn, program, 1)
      assert [%{"placeholder_key" => "input-rules", "policy" => nil}] = placeholder_blocks(body)
    end

    test "the placeholder block carries the current published version of its policy",
         %{conn: conn, program: program, spec: spec} do
      expected = publish_input_rules!()

      body = module_body(conn, program, 1)
      assert_schema(body, "ModuleView", spec)

      assert [%{"placeholder_key" => "input-rules", "policy" => policy}] =
               placeholder_blocks(body)

      assert policy == expected
    end

    test "blocks of other kinds carry policy null", %{conn: conn, program: program} do
      publish_input_rules!()

      for number <- [1, 2] do
        others = other_blocks(module_body(conn, program, number))
        assert others != []
        assert Enum.all?(others, &(&1["policy"] == nil)), "module #{number}"
      end
    end
  end

  describe "GET /api/programs/:slug/handbook" do
    test "each placeholder carries policy null, then the current published version",
         %{conn: conn, program: program, spec: spec} do
      body = handbook(conn, program)
      assert_schema(body, "Handbook", spec)
      assert body["placeholders"] == [%{"key" => "input-rules", "policy" => nil}]

      expected = publish_input_rules!()

      body = handbook(conn, program)
      assert_schema(body, "Handbook", spec)
      assert body["placeholders"] == [%{"key" => "input-rules", "policy" => expected}]
    end
  end
end
