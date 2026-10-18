defmodule Espalier.Catalog.ReportMediaTest do
  @moduledoc """
  `Espalier.Catalog.Pack.Report.run_import/2` with the media of task 0018
  (steps 8 and 10): the import ingests the media files of a copy of the
  demo pack for real, processes the queued assets in the calling process,
  waits for assets that another worker holds, and publishes through the
  media gate of the publisher; with `draft: true` the jobs stay queued.

  The module runs synchronously, as every test of the real ingest path
  does: the SQL sandbox holds the advisory lock of the quota until the test
  ends, and the tests change `config :espalier, :media`.
  """
  use Espalier.DataCase, async: false

  import ExUnit.CaptureIO

  alias Espalier.Catalog.Pack.Report
  alias Espalier.Catalog.{PackImport, Program, ProgramMedia}
  alias Espalier.LearningFixtures
  alias Espalier.Media
  alias Espalier.Media.{Asset, ProcessWorker}
  alias Espalier.MediaFixtures
  alias Espalier.PackFixtures

  @captions "media/assistant-demo-en.vtt"

  setup do
    MediaFixtures.media_env!()
    %{pack: PackFixtures.copy_pack!(PackFixtures.demo_path())}
  end

  defp assets(ids), do: Repo.all(from a in Asset, where: a.id in ^ids, order_by: a.kind)

  defp program_media_count do
    program = Repo.get_by!(Program, slug: LearningFixtures.demo_slug())
    Repo.aggregate(from(m in ProgramMedia, where: m.program_id == ^program.id), :count)
  end

  test "processes the queued media in the calling process and publishes", %{pack: pack} do
    {result, output} = with_io(fn -> Report.run_import(pack) end)

    assert {:ok, %PackImport{status: :published, media_asset_ids: ids}} = result
    assert output =~ "Published ai-assistant-basics-demo"

    # The kinds sort as text.
    assert [
             %Asset{kind: :captions, status: :ready, origin: :pack, ext: "vtt"},
             %Asset{kind: :svg, status: :ready, origin: :pack, ext: "svg"},
             %Asset{kind: :video, status: :ready, origin: :pack, ext: "webm"} = video
           ] = assets(ids)

    assert video.has_audio
    assert video.poster_sha256
    assert {video.width, video.height} == {640, 360}
    assert program_media_count() == 3
  end

  test "a media file that ends failed holds the publish back and prints its path", %{pack: pack} do
    PackFixtures.write!(pack, @captions, MediaFixtures.vtt_with_style())

    {result, output} = with_io(fn -> Report.run_import(pack) end)

    assert {:error, {:media_not_ready, entries}} = result

    assert entries == [
             %{"path" => @captions, "status" => "failed", "failure" => "invalid_captions"}
           ]

    assert output =~ "was not published: media files are not ready"
    assert output =~ "\n#{@captions}: failed\n"
    refute output =~ "Published"

    refute Repo.get_by(Program, slug: LearningFixtures.demo_slug())
    assert [%PackImport{status: :validated}] = Repo.all(PackImport)
  end

  test "with draft: true the media jobs stay queued", %{pack: pack} do
    {result, output} = with_io(fn -> Report.run_import(pack, draft: true) end)

    assert {:ok, %PackImport{status: :validated, media_asset_ids: ids}} = result
    assert output =~ "as draft import"
    assert length(ids) == 3

    for asset <- assets(ids) do
      assert asset.status == :queued
      assert_enqueued(worker: ProcessWorker, args: %{"asset_id" => asset.id})
    end

    refute Repo.get_by(Program, slug: LearningFixtures.demo_slug())
  end

  describe "with another worker on the same jobs" do
    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "espalier-clamd-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        )

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{socket_dir: dir}
    end

    # A fake clamd that answers every stream with OK, except the stream
    # whose content is `held`: that one waits for :release from the test.
    defp fake_clamd(dir, held) do
      socket = Path.join(dir, "clamd.sock")
      test = self()

      start_supervised!(
        Supervisor.child_spec({Task, fn -> listen(socket, test, held) end}, id: make_ref())
      )

      assert_receive :listening
      socket
    end

    defp listen(socket, test, held) do
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, ifaddr: {:local, socket}, active: false, packet: :raw])

      send(test, :listening)
      accept(listen, test, held)
    end

    defp accept(listen, test, held) do
      {:ok, connection} = :gen_tcp.accept(listen)

      handler =
        spawn_link(fn ->
          receive do
            :go -> serve(connection, test, held)
          end
        end)

      :ok = :gen_tcp.controlling_process(connection, handler)
      send(handler, :go)
      accept(listen, test, held)
    end

    defp serve(connection, test, held) do
      {:ok, "zINSTREAM\0"} = :gen_tcp.recv(connection, 10, 5_000)
      content = connection |> read_chunks([]) |> IO.iodata_to_binary()
      send(test, {:scanned, content})

      if content == held do
        send(test, {:held, self()})

        receive do
          :release -> :ok
        end
      end

      :ok = :gen_tcp.send(connection, "stream: OK\0")
      :gen_tcp.close(connection)
    end

    defp read_chunks(connection, chunks) do
      {:ok, <<length::32>>} = :gen_tcp.recv(connection, 4, 5_000)

      if length == 0 do
        Enum.reverse(chunks)
      else
        {:ok, chunk} = :gen_tcp.recv(connection, length, 5_000)
        read_chunks(connection, [chunk | chunks])
      end
    end

    # Releases `handler` once the other media of the import are ready, so
    # that run_import/2 has processed them and waits for the held asset.
    defp release_when_others_ready(handler, held_id, deadline) do
      ready =
        Repo.aggregate(
          from(a in Asset, where: a.id != ^held_id and a.status == :ready),
          :count
        )

      cond do
        ready >= 2 ->
          Process.sleep(700)
          send(handler, :release)

        System.monotonic_time(:millisecond) > deadline ->
          send(handler, :release)
          flunk("the other media did not become ready")

        true ->
          Process.sleep(50)
          release_when_others_ready(handler, held_id, deadline)
      end
    end

    defp count_scans(content, count \\ 0) do
      receive do
        {:scanned, ^content} -> count_scans(content, count + 1)
      after
        0 -> count
      end
    end

    test "the wait ends when the asset that another worker processes is ready", %{
      pack: pack,
      socket_dir: socket_dir
    } do
      content = File.read!(Path.join(pack, @captions))
      MediaFixtures.put_media_env!(clamav_socket: fake_clamd(socket_dir, content))

      # A server took the job of the captions file before the import runs.
      {:ok, captions, :created} =
        Media.ingest_pack_file(%{path: Path.join(pack, @captions), file_name: @captions}, nil)

      worker =
        Task.async(fn ->
          perform_job(ProcessWorker, %{"asset_id" => captions.id, "kind" => "captions"})
        end)

      assert_receive {:held, handler}, 10_000
      assert %Asset{status: :processing} = Repo.get!(Asset, captions.id)

      deadline = System.monotonic_time(:millisecond) + 60_000
      releaser = Task.async(fn -> release_when_others_ready(handler, captions.id, deadline) end)

      {result, output} = with_io(fn -> Report.run_import(pack) end)

      assert {:ok, %PackImport{status: :published, media_asset_ids: ids}} = result
      assert output =~ "Published ai-assistant-basics-demo"
      assert captions.id in ids
      assert Task.await(worker, 10_000) == :ok
      Task.await(releaser, 10_000)

      assert Enum.all?(assets(ids), &(&1.status == :ready))
      assert program_media_count() == 3
      # Only the other worker scanned and processed the captions file.
      assert count_scans(content) == 1
    end
  end
end
