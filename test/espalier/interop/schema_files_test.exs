defmodule Espalier.Interop.SchemaFilesTest do
  use ExUnit.Case, async: true

  alias Espalier.Interop.SchemaFiles

  @files %{
    "a.xsd" => "<xsd:schema/>\n",
    "nested/b.xsd" => "<xsd:schema>b</xsd:schema>\n"
  }

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp archive(files) do
    entries = for {name, data} <- files, do: {String.to_charlist(name), data}
    {:ok, {_name, zip}} = :zip.create(~c"schemas.zip", entries, [:memory])
    zip
  end

  defp source(zip, files \\ @files) do
    %{
      version: "12",
      label: "SCORM 1.2",
      url: "https://example.org/schemas.zip",
      sha256: sha256(zip),
      files: Map.new(files, fn {rel, data} -> {rel, sha256(data)} end)
    }
  end

  defp fetch_once(zip) do
    parent = self()

    fn url ->
      send(parent, {:fetched, url})
      {:ok, zip}
    end
  end

  describe "sources/0" do
    test "pins one HTTPS archive per version with every file by SHA-256" do
      assert [twelve, twenty] = SchemaFiles.sources()
      assert {twelve.version, twenty.version} == {"12", "2004"}
      assert map_size(twelve.files) == 4
      assert map_size(twenty.files) == 17

      for source <- [twelve, twenty] do
        assert String.starts_with?(source.url, "https://")
        assert source.sha256 =~ ~r/\A[0-9a-f]{64}\z/

        for {rel, sha256} <- source.files do
          assert sha256 =~ ~r/\A[0-9a-f]{64}\z/
          refute rel =~ "imsmanifest"
        end
      end

      assert Map.has_key?(twelve.files, "imscp_rootv1p1p2.xsd")
      assert Map.has_key?(twenty.files, "imscp_v1p1.xsd")
    end
  end

  describe "fetch_https/1" do
    test "returns the body as sent, with the user agent of the application" do
      zip = archive(@files)
      parent = self()

      Req.Test.stub(SchemaFiles, fn conn ->
        send(
          parent,
          {:request, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "user-agent")}
        )

        conn
        |> Plug.Conn.put_resp_content_type("application/zip")
        |> Plug.Conn.send_resp(200, zip)
      end)

      assert SchemaFiles.fetch_https("https://example.org/zips/schemas.zip") == {:ok, zip}
      assert_received {:request, "GET", "/zips/schemas.zip", ["Espalier"]}
    end

    test "answers an error for a status other than 200, also for a redirect" do
      Req.Test.stub(SchemaFiles, &Plug.Conn.send_resp(&1, 404, "missing"))
      assert SchemaFiles.fetch_https("https://example.org/a.zip") == {:error, {:http_status, 404}}

      Req.Test.stub(SchemaFiles, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://example.net/b.zip")
        |> Plug.Conn.send_resp(302, "")
      end)

      assert SchemaFiles.fetch_https("https://example.org/a.zip") == {:error, {:http_status, 302}}
    end
  end

  describe "install/3" do
    @tag :tmp_dir
    test "writes the pinned files and fetches nothing once they verify", %{tmp_dir: dir} do
      zip = archive(Map.put(@files, "imsmanifest.xml", "<manifest/>"))
      source = source(zip)

      assert {:ok, [{^source, :installed}]} = SchemaFiles.install(dir, fetch_once(zip), [source])
      assert_received {:fetched, "https://example.org/schemas.zip"}

      assert File.read!(Path.join(dir, "12/a.xsd")) == @files["a.xsd"]
      assert File.read!(Path.join(dir, "12/nested/b.xsd")) == @files["nested/b.xsd"]
      refute File.exists?(Path.join(dir, "12/imsmanifest.xml"))
      refute File.exists?(Path.join(dir, "12.part"))
      assert SchemaFiles.verify(dir, source) == :ok

      assert {:ok, [{^source, :present}]} = SchemaFiles.install(dir, fetch_once(zip), [source])
      refute_received {:fetched, _url}
    end

    @tag :tmp_dir
    test "replaces a version directory whose files do not verify", %{tmp_dir: dir} do
      zip = archive(@files)
      source = source(zip)
      File.mkdir_p!(Path.join(dir, "12"))
      File.write!(Path.join(dir, "12/a.xsd"), "changed")
      File.write!(Path.join(dir, "12/extra.xsd"), "extra")

      assert {:error, problems} = SchemaFiles.verify(dir, source)
      assert "a.xsd differs" in problems
      assert "nested/b.xsd is missing" in problems
      assert "extra.xsd is not pinned" in problems

      assert {:ok, [{^source, :installed}]} = SchemaFiles.install(dir, fetch_once(zip), [source])
      assert SchemaFiles.verify(dir, source) == :ok
      refute File.exists?(Path.join(dir, "12/extra.xsd"))
    end

    @tag :tmp_dir
    test "writes nothing when the archive does not match its SHA-256", %{tmp_dir: dir} do
      source = source(archive(@files))
      other = archive(Map.put(@files, "a.xsd", "<xsd:schema>other</xsd:schema>"))

      assert {:error, ^source, reason} = SchemaFiles.install(dir, fetch_once(other), [source])
      assert reason =~ "does not match its SHA-256"
      refute File.exists?(Path.join(dir, "12"))
    end

    @tag :tmp_dir
    test "writes nothing when a pinned file is missing or differs in the archive", %{
      tmp_dir: dir
    } do
      zip = archive(Map.delete(@files, "nested/b.xsd"))
      source = %{source(zip) | files: source(archive(@files)).files}

      assert {:error, ^source, reason} = SchemaFiles.install(dir, fetch_once(zip), [source])
      assert reason =~ "nested/b.xsd is missing"
      refute File.exists?(Path.join(dir, "12"))

      changed = archive(Map.put(@files, "a.xsd", "changed"))
      source = %{source(changed) | files: source(archive(@files)).files}

      assert {:error, ^source, reason} = SchemaFiles.install(dir, fetch_once(changed), [source])
      assert reason =~ "a.xsd differs"
    end

    @tag :tmp_dir
    test "fetches the archive with Req by default", %{tmp_dir: dir} do
      zip = archive(@files)
      source = source(zip)
      Req.Test.stub(SchemaFiles, &Plug.Conn.send_resp(&1, 200, zip))

      assert {:ok, [{^source, :installed}]} =
               SchemaFiles.install(dir, &SchemaFiles.fetch_https/1, [source])

      assert SchemaFiles.verify(dir, source) == :ok
    end

    @tag :tmp_dir
    test "reports a failed fetch", %{tmp_dir: dir} do
      source = source(archive(@files))
      fetch = fn _url -> {:error, :nxdomain} end

      assert {:error, ^source, reason} = SchemaFiles.install(dir, fetch, [source])
      assert reason =~ "could not be fetched"
      assert reason =~ "nxdomain"
    end
  end
end
