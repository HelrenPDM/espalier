defmodule Espalier.DevOidc.Fixtures do
  @moduledoc """
  The invented users of the mock OIDC provider (task 0006, step 15). Every
  address lies under `example.org` or `example.net`, and every identifier
  is made up. Every profile also offers `deny`, which answers
  `access_denied`.
  """

  @doc "The fixture ids of `profile` in the order of the sign-in page."
  def ids(:entra), do: ["ada", "ben"]
  def ids(:google), do: ["gina", "gus", "uma"]
  def ids(:oidc), do: ["olga"]

  @doc "The claims of fixture `id` of `profile`, or `nil`."
  def claims(:entra, "ada") do
    %{
      "sub" => "pw-7Hq2LxVb9c0Ks1Zt4Ad8nE3mRfYu6WgJ",
      "oid" => "0b6f3c1e-9a2d-4c7e-8f15-3d2a6b9e4c01",
      "tid" => tenant_id(),
      "name" => "Ada Example",
      "preferred_username" => "ada@example.org",
      "roles" => ["Espalier.Author"],
      "sid" => "sid-ada"
    }
  end

  def claims(:entra, "ben") do
    %{
      "sub" => "pw-2Mw8RpDt5n1Qa9Xk3Hc7vB0eGyLs4UjF",
      "oid" => "5e2a9d47-1c3b-4f86-a0d2-7b8c9e1f2a03",
      "tid" => tenant_id(),
      "name" => "Ben Example",
      "email" => "ben@example.org",
      "xms_edov" => true,
      "amr" => ["pwd", "mfa"],
      "sid" => "sid-ben"
    }
  end

  def claims(:google, "gina") do
    %{
      "sub" => "104729384756102938475",
      "hd" => "example.org",
      "email" => "gina@example.org",
      "email_verified" => true,
      "name" => "Gina Example"
    }
  end

  def claims(:google, "gus") do
    %{
      "sub" => "104729384756102938476",
      "hd" => "example.net",
      "email" => "gus@example.net",
      "email_verified" => true,
      "name" => "Gus Example"
    }
  end

  def claims(:google, "uma") do
    %{
      "sub" => "104729384756102938477",
      "hd" => "example.org",
      "email" => "uma@example.org",
      "email_verified" => false,
      "name" => "Uma Example"
    }
  end

  def claims(:oidc, "olga") do
    %{
      "sub" => "olga-8f3e2d1c",
      "name" => "Olga Example",
      "email" => "olga@example.org",
      "email_verified" => true,
      "roles" => ["espalier-admins"],
      "sid" => "sid-olga"
    }
  end

  def claims(_profile, _id), do: nil

  defp tenant_id, do: Espalier.DevOidc.config()[:tenant_id]
end
