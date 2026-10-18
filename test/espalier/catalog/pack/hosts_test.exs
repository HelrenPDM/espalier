defmodule Espalier.Catalog.Pack.HostsTest do
  @moduledoc """
  Task 0018, steps 10 and 23 (ASVS 1.2.2): `Hosts.check/2` reports every
  external video file and every embed whose host and port the allowlists
  of the installation do not admit, at the file and the line of its block,
  and compares hosts and ports as `Espalier.Credentials.Webhook` does.
  """
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{Hosts, Loader}

  @lesson "modules/01-basics/lessons/02-practice.md"
  @check "modules/02-checking/lessons/01-check.md"

  @none %{external: [], embed: []}

  # Appends `lines` to the lesson `rel` and returns the number of the first.
  defp append!(pack, rel, lines) do
    content = read!(pack, rel)
    write!(pack, rel, content <> "\n" <> Enum.join(lines, "\n") <> "\n")
    (content |> String.split("\n") |> length()) + 1
  end

  defp loaded!(pack) do
    assert {:ok, loaded} = Loader.load(pack)
    loaded
  end

  defp messages(entries), do: Enum.map(entries, &{&1.file, &1.line, &1.message})

  setup do
    pack = copy_pack!("minimal")

    first =
      append!(pack, @lesson, [
        ":::video{src=https://cdn.example.org/clips/a.mp4 title=A provenance=invented}",
        "Transcript.",
        ":::",
        "",
        ":::video{embed=https://player.example.org/embed/1 title=B provenance=invented}",
        "Transcript.",
        ":::",
        "",
        ":::video{src=media/clip.webm title=C provenance=invented}",
        "Transcript.",
        ":::",
        "",
        ":::figure{src=media/photo.png alt=D provenance=invented}",
        ":::"
      ])

    second =
      append!(pack, @check, [
        ":::video{src=https://CDN.Example.org:8443/b.webm title=E provenance=invented}",
        "Transcript.",
        ":::"
      ])

    %{pack: pack, external: first, embed: first + 4, second: second}
  end

  test "reports every external src and embed with empty allowlists, at file and line", ctx do
    assert ctx.pack |> loaded!() |> Hosts.check(@none) |> messages() == [
             {@lesson, ctx.external, "host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS"},
             {@lesson, ctx.embed, "host player.example.org is not in MEDIA_EMBED_HOSTS"},
             {@check, ctx.second, "host cdn.example.org:8443 is not in MEDIA_EXTERNAL_HOSTS"}
           ]
  end

  test "admits listed hosts, compares hosts in lower case, and ignores media paths", ctx do
    hosts = %{
      external: [{"cdn.example.org", nil}, {"cdn.example.org", 8443}],
      embed: [{"Player.Example.org", nil}]
    }

    assert ctx.pack |> loaded!() |> Hosts.check(hosts) == []
  end

  test "an entry without a port admits the default port 443 only", ctx do
    loaded = loaded!(ctx.pack)

    assert loaded |> Hosts.check(%{external: [{"cdn.example.org", nil}], embed: []}) |> messages() ==
             [
               {@lesson, ctx.embed, "host player.example.org is not in MEDIA_EMBED_HOSTS"},
               {@check, ctx.second, "host cdn.example.org:8443 is not in MEDIA_EXTERNAL_HOSTS"}
             ]
  end

  test "an entry with a port admits that port only", ctx do
    hosts = %{external: [{"cdn.example.org", 8443}], embed: [{"player.example.org", 443}]}

    assert ctx.pack |> loaded!() |> Hosts.check(hosts) |> messages() == [
             {@lesson, ctx.external, "host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS"}
           ]
  end

  test "an explicit port 443 equals the default port", %{pack: pack} do
    line =
      append!(pack, @lesson, [
        ":::video{src=https://cdn.example.org:443/c.mp4 title=F provenance=invented}",
        "Transcript.",
        ":::"
      ])

    entries = pack |> loaded!() |> Hosts.check(%{external: [{"cdn.example.org", nil}], embed: []})
    refute line in Enum.map(entries, & &1.line)
  end

  test "an embed host does not admit an external file, nor the other way round", ctx do
    hosts = %{external: [{"player.example.org", nil}], embed: [{"cdn.example.org", nil}]}

    assert ctx.pack |> loaded!() |> Hosts.check(hosts) |> messages() == [
             {@lesson, ctx.external, "host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS"},
             {@lesson, ctx.embed, "host player.example.org is not in MEDIA_EMBED_HOSTS"},
             {@check, ctx.second, "host cdn.example.org:8443 is not in MEDIA_EXTERNAL_HOSTS"}
           ]
  end

  test "leaves values that are no https URL with a host to the validator" do
    pack = copy_pack!("minimal")

    append!(pack, @lesson, [
      ":::video{src=http://cdn.example.org/a.mp4 title=A provenance=invented}",
      ":::",
      ":::video{embed=https:/player title=B provenance=invented}",
      ":::",
      ":::video{src=media/a.webm embed=javascript:alert(1) title=C provenance=invented}",
      ":::"
    ])

    assert pack |> loaded!() |> Hosts.check(@none) == []
  end

  test "reads a loaded map without lessons and the hosts of the installation" do
    assert Hosts.check(%{}, @none) == []
    assert Hosts.check(%{modules: []}, @none) == []

    # The test configuration keeps both lists empty.
    assert Hosts.installation() == @none
  end
end
