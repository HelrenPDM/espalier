defmodule Espalier.MediaTest do
  @moduledoc """
  The media library context of task 0018 (steps 4, 7 and 8, step 23
  "Media ingest, deduplication by source and by delivery digest, origin and
  `updated_at` on a hit, state changes, uses and deletion").

  Every test runs with a store of its own below `System.tmp_dir!/0`
  (`Espalier.MediaFixtures.media_env!/1`). The module is synchronous: the
  ingest takes the advisory lock of the quota, which the SQL sandbox holds
  until the test ends, the tests change `config :espalier, :media`, and the
  deletion tests remove store files.
  """
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.{LearningFixtures, Media, MediaFixtures, PackFixtures}
  alias Espalier.Media.{Asset, ProcessWorker, Store, Svg}
  alias Espalier.Test.LogForwarder
  alias Espalier.Workbench.{PackDraft, PackDraftMedia}

  @mib 1_048_576
  @gib 1024 * @mib

  setup do
    dir = MediaFixtures.media_env!()
    user = user_fixture()

    %{
      dir: dir,
      user: user,
      author: %{Scope.for_user(user) | roles: [:learner, :author]},
      learner: Scope.for_user(user_fixture())
    }
  end

  # Writes an upload below uploads/, as Plug.Upload does with PLUG_TMPDIR,
  # and returns the argument of ingest/3.
  defp upload!(name, content) do
    dir = Path.join(Store.uploads_root(), "plug-test")
    File.mkdir_p!(dir)
    path = Path.join(dir, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %{path: path, file_name: name}
  end

  # Writes a pack file below the test root, beside the directories of the
  # store, and returns the argument of ingest_pack_file/2.
  defp pack_file!(name, content) do
    dir = Path.join(Media.dir(), "pack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, Path.basename(name))
    File.write!(path, content)
    %{path: path, file_name: name}
  end

  defp sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  defp incoming_names do
    case File.ls(Store.incoming_root()) do
      {:ok, names} -> Enum.sort(names)
      {:error, :enoent} -> []
    end
  end

  defp stored_files do
    root = Store.files_root()
    if File.dir?(root), do: root |> Path.join("**/*.*") |> Path.wildcard(), else: []
  end

  defp asset_count, do: Repo.aggregate(Asset, :count)

  defp set_updated_at!(%Asset{id: id}, updated_at) do
    {1, _rows} =
      Repo.update_all(from(a in Asset, where: a.id == ^id), set: [updated_at: updated_at])

    Repo.get!(Asset, id)
  end

  defp an_hour_ago, do: DateTime.add(DateTime.utc_now(:second), -3600, :second)

  ## Ingest

  describe "ingest/3 and ingest_pack_file/2" do
    test "an upload without the role author answers forbidden and leaves the file", %{
      learner: learner
    } do
      file = upload!("captions.vtt", MediaFixtures.vtt())

      assert Media.ingest(learner, file) == {:error, :forbidden}
      assert File.exists?(file.path)
      assert asset_count() == 0
      assert incoming_names() == []
    end

    test "the detection errors answer before anything is stored", %{author: author} do
      cases = [
        {"notes.png", "plain text, no image", :unsupported_type},
        {"photo.mp4", MediaFixtures.png(2, 2), :extension_mismatch},
        {"huge.png", MediaFixtures.png_header(10_000, 10_000), :too_many_pixels}
      ]

      for {name, content, reason} <- cases do
        upload = upload!(name, content)
        assert Media.ingest(author, upload) == {:error, reason}
        assert File.exists?(upload.path)

        assert Media.ingest_pack_file(pack_file!("media/" <> name, content), nil) ==
                 {:error, reason}
      end

      assert asset_count() == 0
      assert incoming_names() == []
      assert all_enqueued(worker: ProcessWorker) == []
    end

    test "every kind answers media_too_large above its own limit", %{author: author} do
      MediaFixtures.put_media_env!(
        image_max_mb: 1,
        video_max_mb: 1,
        svg_max_bytes: 200,
        captions_max_bytes: 100
      )

      too_large = [
        {"photo.png", MediaFixtures.png_header(10, 10, @mib)},
        {"clip.webm", <<0x1A, 0x45, 0xDF, 0xA3>> <> :binary.copy(<<0>>, @mib)},
        {"chart.svg", MediaFixtures.growing_svg(150)},
        {"captions.vtt", MediaFixtures.vtt(String.duplicate("x", 80))}
      ]

      for {name, content} <- too_large do
        assert Media.ingest(author, upload!(name, content)) == {:error, :media_too_large}

        assert Media.ingest_pack_file(pack_file!(name, content), nil) ==
                 {:error, :media_too_large}
      end

      # The limit of the detected kind applies: 100 bytes of captions pass.
      captions = MediaFixtures.vtt(String.duplicate("x", 100 - byte_size(MediaFixtures.vtt(""))))
      assert byte_size(captions) == 100

      assert {:ok, %Asset{kind: :captions}, :created} =
               Media.ingest(author, upload!("c.vtt", captions))

      assert asset_count() == 1
    end

    test "a new upload is queued with its title, source name, sizes, creator, job and audit event",
         %{author: author, user: user} do
      content = MediaFixtures.vtt()
      upload = upload!("Lesson captions.en.vtt", content)

      assert {:ok, %Asset{} = asset, :created} = Media.ingest(author, upload)

      assert %Asset{
               kind: :captions,
               status: :queued,
               title: "Lesson captions.en",
               source_name: "Lesson captions.en.vtt",
               origin: :upload,
               progress: 0,
               sha256: nil,
               bytes: nil
             } = asset

      assert asset.source_sha256 == sha256(content)
      assert asset.incoming_bytes == byte_size(content)
      assert asset.created_by_id == user.id
      assert Repo.get!(Asset, asset.id).status == :queued

      # The upload moved to incoming/<id>.
      refute File.exists?(upload.path)
      assert File.read!(Store.incoming_path(asset.id)) == content
      assert incoming_names() == [asset.id]

      assert_enqueued(
        worker: ProcessWorker,
        queue: :media,
        args: %{"asset_id" => asset.id, "kind" => "captions"}
      )

      assert [%AuditEvent{} = event] =
               Repo.all(from e in AuditEvent, where: e.action == "media.uploaded")

      assert event.subject_id == asset.id
      assert event.actor_id == user.id
      assert event.details == %{"kind" => "captions"}
    end

    test "a pack file is copied, takes the actor as creator, and writes no audit event", %{
      user: user
    } do
      content = <<0x1A, 0x45, 0xDF, 0xA3>> <> :crypto.strong_rand_bytes(64)
      file = pack_file!("media/clips/intro.webm", content)

      assert {:ok, %Asset{} = asset, :created} = Media.ingest_pack_file(file, user.id)

      assert %Asset{kind: :video, status: :queued, origin: :pack, title: "intro"} = asset
      assert asset.source_name == "intro.webm"
      assert asset.created_by_id == user.id
      assert File.read!(file.path) == content
      assert File.read!(Store.incoming_path(asset.id)) == content

      assert_enqueued(
        worker: ProcessWorker,
        queue: :media_video,
        args: %{"asset_id" => asset.id, "kind" => "video"}
      )

      refute Repo.exists?(from e in AuditEvent, where: e.action == "media.uploaded")

      assert {:ok, %Asset{created_by_id: nil}, :created} =
               Media.ingest_pack_file(pack_file!("media/b.vtt", MediaFixtures.vtt("b")), nil)
    end

    test "the title is the file name without its extension, cut to 255 characters, without U+0000 and with invalid UTF-8 replaced, and the source name keeps its extension",
         %{author: author} do
      long = String.duplicate("ä", 300)

      cases = [
        {long <> ".vtt", String.duplicate("ä", 255), String.duplicate("ä", 251) <> ".vtt"},
        {"cap\0tions.vtt", "captions", "captions.vtt"},
        {"caption<<0xFF>>.vtt", nil, nil},
        {"dir/sub/name.vtt", "name", "name.vtt"}
      ]

      for {{name, title, source_name}, n} <- Enum.with_index(cases) do
        name = String.replace(name, "<<0xFF>>", <<0xFF>>)

        assert {:ok, asset, :created} =
                 Media.ingest(author, upload!(name, MediaFixtures.vtt("cue #{n}")))

        if title do
          assert asset.title == title
          assert asset.source_name == source_name
        else
          assert asset.title == "caption_"
          assert asset.source_name == "caption_.vtt"
        end

        assert String.valid?(asset.title)
        assert String.length(asset.title) <= 255
      end
    end

    test "a second upload of the same source answers the asset with :existing, deletes the copy and becomes origin upload",
         %{author: author} do
      content = MediaFixtures.vtt()

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      old = set_updated_at!(asset, an_hour_ago())

      upload = upload!("again.vtt", content)
      assert {:ok, existing, :existing} = Media.ingest(author, upload)

      assert existing.id == asset.id
      assert existing.origin == :upload
      assert DateTime.compare(existing.updated_at, old.updated_at) == :gt
      assert Repo.get!(Asset, asset.id).origin == :upload

      # The placed copy is gone, the incoming file of the asset stays.
      refute File.exists?(upload.path)
      assert incoming_names() == [asset.id]
      assert asset_count() == 1
      assert length(all_enqueued(worker: ProcessWorker)) == 1

      assert Repo.aggregate(from(e in AuditEvent, where: e.action == "media.uploaded"), :count) ==
               0
    end

    test "a pack file of an uploaded source keeps origin upload" do
      content = MediaFixtures.vtt()
      user = user_fixture()
      scope = %{Scope.for_user(user) | roles: [:author]}
      assert {:ok, asset, :created} = Media.ingest(scope, upload!("a.vtt", content))

      assert {:ok, existing, :existing} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      assert existing.id == asset.id
      assert existing.origin == :upload
    end

    test "an asset in processing keeps its updated_at on a hit", %{author: author} do
      content = MediaFixtures.vtt()
      assert {:ok, asset, :created} = Media.ingest(author, upload!("a.vtt", content))

      {1, _rows} =
        Repo.update_all(from(a in Asset, where: a.id == ^asset.id),
          set: [status: :processing, updated_at: an_hour_ago()]
        )

      before = Repo.get!(Asset, asset.id)
      assert {:ok, existing, :existing} = Media.ingest(author, upload!("b.vtt", content))
      assert existing.updated_at == before.updated_at
      assert Repo.get!(Asset, asset.id).updated_at == before.updated_at
    end

    test "a file equal to the delivery file of a ready asset answers that asset", %{
      author: author
    } do
      content = MediaFixtures.vtt("delivered")
      file = pack_file!("media/source.vtt", content)
      ready = MediaFixtures.stored_asset!(file.path, :captions, "vtt", %{duration_ms: 1500})
      ready = set_updated_at!(ready, an_hour_ago())

      upload = upload!("exported.vtt", content)
      assert {:ok, existing, :existing} = Media.ingest(author, upload)
      assert existing.id == ready.id
      assert existing.origin == :upload
      assert DateTime.compare(existing.updated_at, ready.updated_at) == :gt
      refute File.exists?(upload.path)
      assert incoming_names() == []

      assert {:ok, %Asset{id: id}, :existing} =
               Media.ingest_pack_file(pack_file!("media/again.vtt", content), nil)

      assert id == ready.id
      assert asset_count() == 1
      assert all_enqueued(worker: ProcessWorker) == []
    end

    test "a failed asset of the same source is reset to queued with a new job and the new copy",
         %{author: author} do
      content = MediaFixtures.vtt_with_style()

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      :ok = Media.process(asset.id)

      assert %Asset{status: :failed, failure: :invalid_captions, failure_detail: :style} =
               Repo.get!(Asset, asset.id)

      assert incoming_names() == []

      assert {:ok, retried, :existing} = Media.ingest(author, upload!("again.vtt", content))
      assert retried.id == asset.id

      assert %Asset{
               status: :queued,
               failure: nil,
               failure_detail: nil,
               progress: 0,
               origin: :upload
             } = Repo.get!(Asset, asset.id)

      assert retried.incoming_bytes == byte_size(content)
      assert incoming_names() == [asset.id]
      assert File.read!(Store.incoming_path(asset.id)) == content

      assert [_first, _second] =
               all_enqueued(worker: ProcessWorker, args: %{"asset_id" => asset.id})
    end

    test "an ingest above the storage quota answers storage_full and stores nothing", %{
      author: author
    } do
      MediaFixtures.put_media_env!(storage_max_gb: 1)
      MediaFixtures.insert_asset!(%{bytes: @gib - 10})

      content = MediaFixtures.vtt()
      upload = upload!("a.vtt", content)
      assert Media.ingest(author, upload) == {:error, :storage_full}

      assert Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil) ==
               {:error, :storage_full}

      assert asset_count() == 1
      assert incoming_names() == []
      assert all_enqueued(worker: ProcessWorker) == []
      refute Repo.exists?(from e in AuditEvent, where: e.action == "media.uploaded")

      # Exactly at the quota the ingest passes.
      MediaFixtures.insert_asset!(%{bytes: 10 - byte_size(content)})
      assert {:ok, _asset, :created} = Media.ingest(author, upload!("b.vtt", content))
    end

    test "the retry of a failed asset checks the quota", %{author: author} do
      content = MediaFixtures.vtt_with_style()
      assert {:ok, asset, :created} = Media.ingest(author, upload!("a.vtt", content))
      :ok = Media.process(asset.id)

      MediaFixtures.put_media_env!(storage_max_gb: 1)
      MediaFixtures.insert_asset!(%{bytes: @gib - 10})

      assert Media.ingest(author, upload!("b.vtt", content)) == {:error, :storage_full}
      assert %Asset{status: :failed} = Repo.get!(Asset, asset.id)
      assert incoming_names() == []
    end

    test "a full volume and an exhausted disk quota while the file is placed answer storage_full" do
      # No test can fill the volume, so the reasons go to the function that
      # answers a failed placement into incoming/.
      assert Media.placement_error(:enospc) == {:error, :storage_full}
      assert Media.placement_error(:edquot) == {:error, :storage_full}

      for reason <- [:eacces, :eio, :enoent] do
        assert_raise File.Error, ~r/could not place "incoming"/, fn ->
          Media.placement_error(reason)
        end
      end
    end
  end

  ## Processing

  describe "process/1 and process_now/1" do
    test "a queued captions file becomes ready with digest, size, facts and progress 100" do
      content = MediaFixtures.vtt()

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      assert %Asset{} = ready = Media.process_now(asset)

      assert %Asset{
               status: :ready,
               ext: "vtt",
               incoming_bytes: 0,
               progress: 100,
               duration_ms: 1500,
               failure: nil,
               poster_sha256: nil
             } = ready

      assert ready.sha256 == sha256(content)
      assert ready.bytes == byte_size(content)
      assert File.read!(Store.path(ready.sha256, "vtt")) == content
      refute File.exists?(Store.incoming_path(asset.id))
      assert MediaFixtures.work_dirs(asset.id) == []
      assert Media.url(ready) == "/media/#{ready.sha256}.vtt"
    end

    test "PNG images become WebP files with the facts of the delivery file" do
      assert {:ok, opaque, :created} =
               Media.ingest_pack_file(
                 pack_file!("media/opaque.png", MediaFixtures.png(4, 3)),
                 nil
               )

      assert {:ok, alpha, :created} =
               Media.ingest_pack_file(
                 pack_file!("media/alpha.png", MediaFixtures.png(5, 2, alpha: true)),
                 nil
               )

      assert %Asset{status: :ready, ext: "webp", width: 4, height: 3, has_alpha: false} =
               opaque = Media.process_now(opaque)

      assert %Asset{status: :ready, ext: "webp", width: 5, height: 2, has_alpha: true} =
               alpha = Media.process_now(alpha)

      for asset <- [opaque, alpha] do
        assert <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> =
                 File.read!(Store.path(asset.sha256, "webp"))

        assert asset.bytes == File.stat!(Store.path(asset.sha256, "webp")).size
        refute asset.animated
        assert asset.incoming_bytes == 0
        assert MediaFixtures.work_dirs(asset.id) == []
      end
    end

    test "a second process/1 of the same asset changes nothing" do
      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt()), nil)

      :ok = Media.process(asset.id)
      ready = set_updated_at!(Repo.get!(Asset, asset.id), an_hour_ago())

      assert Media.process(asset.id) == :ok
      assert Repo.get!(Asset, asset.id) == ready

      # An asset that another worker holds is left alone as well.
      assert {:ok, taken, :created} =
               Media.ingest_pack_file(pack_file!("media/b.vtt", MediaFixtures.vtt("b")), nil)

      {1, _rows} =
        Repo.update_all(from(a in Asset, where: a.id == ^taken.id), set: [status: :processing])

      assert Media.process(taken.id) == :ok
      assert %Asset{status: :processing} = Repo.get!(Asset, taken.id)
      assert File.exists?(Store.incoming_path(taken.id))

      # An unknown asset as well.
      assert Media.process(Ecto.UUID.generate()) == :ok
    end

    test "a failure sets failed with code and reason tag, logs the asset id and removes the incoming file and the work directory" do
      LogForwarder.attach()

      cases = [
        {"media/a.vtt", MediaFixtures.vtt_with_style(), :invalid_captions, :style},
        {"media/b.svg",
         ~s(<?xml version="1.0"?><!DOCTYPE svg><svg xmlns="http://www.w3.org/2000/svg"/>),
         :invalid_svg, :doctype}
      ]

      for {path, content, failure, detail} <- cases do
        assert {:ok, asset, :created} = Media.ingest_pack_file(pack_file!(path, content), nil)
        assert asset.incoming_bytes > 0

        assert %Asset{
                 status: :failed,
                 failure: ^failure,
                 failure_detail: ^detail,
                 incoming_bytes: 0,
                 sha256: nil
               } = Media.process_now(asset)

        id = asset.id

        message =
          "media asset #{id} failed: #{failure}" <> if(detail, do: " (#{detail})", else: "")

        assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}

        refute File.exists?(Store.incoming_path(asset.id))
        assert MediaFixtures.work_dirs(asset.id) == []
      end

      assert stored_files() == []
    end

    test "fail/2 fails an asset in processing with interrupted and logs it" do
      LogForwarder.attach()

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt()), nil)

      # Only an asset in processing.
      assert Media.fail(asset.id, :interrupted) == 0
      refute_received {:log_event, %{level: :error}}

      {1, _rows} =
        Repo.update_all(from(a in Asset, where: a.id == ^asset.id), set: [status: :processing])

      assert Media.fail(asset.id, :interrupted) == 1

      assert %Asset{status: :failed, failure: :interrupted, incoming_bytes: 0} =
               Repo.get!(Asset, asset.id)

      id = asset.id

      message = "media asset #{id} failed: interrupted"
      assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}
    end

    test "outputs above the quota fail the ready transition with storage_full and never enter the store" do
      LogForwarder.attach()
      MediaFixtures.put_media_env!(storage_max_gb: 1)
      source = MediaFixtures.growing_svg(1000)
      {:ok, delivery, _facts} = Svg.sanitize(source)
      assert byte_size(delivery) > byte_size(source)

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.svg", source), nil)

      # The source fits, its delivery file does not.
      MediaFixtures.insert_asset!(%{bytes: @gib - Media.used_bytes() - 10})

      assert %Asset{
               status: :failed,
               failure: :storage_full,
               incoming_bytes: 0,
               sha256: nil,
               bytes: nil
             } = Media.process_now(asset)

      id = asset.id

      message = "media asset #{id} failed: storage_full"
      assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}

      refute File.exists?(Store.path(sha256(delivery), "svg"))
      assert stored_files() == []
      refute File.exists?(Store.incoming_path(asset.id))
      assert MediaFixtures.work_dirs(asset.id) == []
    end
  end

  ## Scan

  describe "the scan through clamd" do
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

    # A fake clamd on a Unix socket in `dir`: it accepts connections one
    # after the other, reads each stream, reports the content to the test,
    # and answers with `reply.(content)`, or closes for :close.
    defp fake_clamd(dir, reply) do
      socket = Path.join(dir, "clamd.sock")
      test = self()

      start_supervised!(
        Supervisor.child_spec({Task, fn -> listen(socket, test, reply) end}, id: make_ref())
      )

      assert_receive :listening
      socket
    end

    defp listen(socket, test, reply) do
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, ifaddr: {:local, socket}, active: false, packet: :raw])

      send(test, :listening)
      accept(listen, test, reply)
    end

    defp accept(listen, test, reply) do
      {:ok, connection} = :gen_tcp.accept(listen)
      {:ok, "zINSTREAM\0"} = :gen_tcp.recv(connection, 10, 5_000)
      content = connection |> read_chunks([]) |> IO.iodata_to_binary()
      send(test, {:scanned, content})

      case reply.(content) do
        :close -> :ok
        answer -> :ok = :gen_tcp.send(connection, answer)
      end

      :gen_tcp.close(connection)
      accept(listen, test, reply)
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

    test "a finding fails the asset with malware_found, deletes the incoming file and logs upload_validation",
         %{socket_dir: socket_dir, author: author, user: user} do
      socket = fake_clamd(socket_dir, fn _content -> "stream: Win.Test.EICAR_HDB-1 FOUND\0" end)
      MediaFixtures.put_media_env!(clamav_socket: socket)
      ref = attach_security_events()
      content = MediaFixtures.vtt("infected")

      assert {:ok, asset, :created} = Media.ingest(author, upload!("a.vtt", content))

      assert %Asset{
               status: :failed,
               failure: :malware_found,
               failure_detail: nil,
               incoming_bytes: 0
             } =
               Media.process_now(asset)

      assert_received {:scanned, ^content}
      refute File.exists?(Store.incoming_path(asset.id))
      assert MediaFixtures.work_dirs(asset.id) == []
      assert stored_files() == []

      user_id = user.id

      assert_received {^ref,
                       %{
                         name: :upload_validation,
                         reason: "malware_found:Win.Test.EICAR_HDB-1",
                         user_id: ^user_id
                       }}
    end

    test "a finding in a pack file without an actor logs the event without a user", %{
      socket_dir: socket_dir
    } do
      socket = fake_clamd(socket_dir, fn _content -> "stream: Bad Name/1 FOUND\0" end)
      MediaFixtures.put_media_env!(clamav_socket: socket)
      ref = attach_security_events()

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt()), nil)

      assert %Asset{failure: :malware_found} = Media.process_now(asset)

      assert_received {^ref,
                       %{name: :upload_validation, reason: "malware_found:Bad_Name_1"} = event}

      refute Map.has_key?(event, :user_id)
    end

    test "an error reply fails the asset with scan_failed and its reason tag and logs the asset id",
         %{socket_dir: socket_dir} do
      LogForwarder.attach()
      socket = fake_clamd(socket_dir, fn _content -> "INSTREAM size limit exceeded. ERROR\0" end)
      MediaFixtures.put_media_env!(clamav_socket: socket)

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt()), nil)

      assert %Asset{status: :failed, failure: :scan_failed, failure_detail: :size_limit} =
               Media.process_now(asset)

      id = asset.id

      message = "media asset #{id} failed: scan_failed (size_limit)"
      assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}

      refute File.exists?(Store.incoming_path(asset.id))
    end

    test "a socket without a server fails the asset with scan_failed and connect", %{
      socket_dir: socket_dir
    } do
      MediaFixtures.put_media_env!(clamav_socket: Path.join(socket_dir, "missing.sock"))

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt()), nil)

      assert %Asset{status: :failed, failure: :scan_failed, failure_detail: :connect} =
               Media.process_now(asset)
    end

    test "a clean reply lets the processing go on, and without a socket no scan runs", %{
      socket_dir: socket_dir
    } do
      socket = fake_clamd(socket_dir, fn _content -> "stream: OK\0" end)

      assert {:ok, unscanned, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", MediaFixtures.vtt("a")), nil)

      assert %Asset{status: :ready} = Media.process_now(unscanned)
      refute_received {:scanned, _content}

      MediaFixtures.put_media_env!(clamav_socket: socket)
      content = MediaFixtures.vtt("b")

      assert {:ok, scanned, :created} =
               Media.ingest_pack_file(pack_file!("media/b.vtt", content), nil)

      assert %Asset{status: :ready} = Media.process_now(scanned)
      assert_received {:scanned, ^content}
    end

    test "during the scan the asset is processing, and a deletion then leaves no row and no stored file",
         %{socket_dir: socket_dir, author: author} do
      test = self()
      content = MediaFixtures.vtt("deleted while scanned")

      socket =
        fake_clamd(socket_dir, fn _content ->
          [asset] = Repo.all(Asset)
          send(test, {:during_scan, asset.status, asset.progress})
          :ok = Media.delete_asset(author, asset.id)
          "stream: OK\0"
        end)

      MediaFixtures.put_media_env!(clamav_socket: socket)

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      assert Media.process(asset.id) == :ok
      assert_received {:during_scan, :processing, 0}
      refute Repo.get(Asset, asset.id)
      refute File.exists?(Store.path(sha256(content), "vtt"))
      assert stored_files() == []
      refute File.exists?(Store.incoming_path(asset.id))
      assert MediaFixtures.work_dirs(asset.id) == []
    end
  end

  ## Uses and deletion

  # A ready asset with a delivery file and, for `poster: true`, a poster in
  # the store.
  defp stored!(attrs \\ %{}, opts \\ []) do
    content = Keyword.get(opts, :content, "<svg>#{System.unique_integer()}</svg>")
    sha = MediaFixtures.store_file!(content, Map.get(attrs, :ext, "svg"))

    poster =
      if Keyword.get(opts, :poster, false),
        do: MediaFixtures.store_file!("poster #{System.unique_integer()}", "webp")

    MediaFixtures.insert_asset!(
      Map.merge(
        %{
          sha256: sha,
          bytes: byte_size(content),
          poster_sha256: poster,
          poster_bytes: poster && 6
        },
        attrs
      )
    )
  end

  defp draft_with!(asset, title, path) do
    draft = Repo.insert!(%PackDraft{title: title, lock_version: 1})
    Repo.insert!(%PackDraftMedia{pack_draft_id: draft.id, media_asset_id: asset.id, path: path})
    draft
  end

  defp validated_import_with!(asset) do
    Repo.insert!(%PackImport{
      pack_key: "media-pack",
      pack_version: "1.0.0",
      status: :validated,
      report: %{},
      payload: %{},
      media_asset_ids: [asset.id]
    })
  end

  # Publishes the demo pack with the ready assets of its media and returns
  # the program and the asset of each path.
  defp publish_demo! do
    program = LearningFixtures.publish_demo!()
    mapping = MediaFixtures.media_for(PackFixtures.demo_path())
    {program, Map.new(mapping, fn {path, id} -> {path, Repo.get!(Asset, id)} end)}
  end

  defp demo_asset!(path) do
    {program, assets} = publish_demo!()
    {program, Map.fetch!(assets, path)}
  end

  describe "uses/1 and delete_asset/2" do
    test "uses/1 lists the published programs, the drafts and the validated imports" do
      {program, asset} = demo_asset!("media/release-checks.svg")
      draft = draft_with!(asset, "Draft one", "media/release-checks.svg")
      pack_import = validated_import_with!(asset)

      assert %{programs: programs, drafts: drafts, imports: imports} = Media.uses(asset)
      assert programs == [%{slug: program.slug, title: program.title}]
      assert drafts == [%{id: draft.id, title: "Draft one", path: "media/release-checks.svg"}]

      assert [%{id: id, pack_key: "media-pack", inserted_at: %DateTime{}}] = imports
      assert id == pack_import.id

      assert Media.uses(stored!()) == %{programs: [], drafts: [], imports: []}
    end

    test "an asset of a published program answers asset_in_use with its uses", %{author: author} do
      {program, asset} = demo_asset!("media/release-checks.svg")

      assert {:error, {:asset_in_use, %{programs: [%{slug: slug}], drafts: []}}} =
               Media.delete_asset(author, asset.id)

      assert slug == program.slug
      assert Repo.get(Asset, asset.id)
      assert File.exists?(Store.path(asset.sha256, "svg"))
      refute Repo.exists?(from e in AuditEvent, where: e.action == "media.deleted")
    end

    test "an asset of a draft answers asset_in_use", %{author: author} do
      asset = stored!()
      draft = draft_with!(asset, "Draft two", "media/chart.svg")

      assert {:error, {:asset_in_use, %{programs: [], drafts: [%{id: id}]}}} =
               Media.delete_asset(author, asset.id)

      assert id == draft.id
      assert Repo.get(Asset, asset.id)
    end

    test "an unused asset is deleted with the audit event media.deleted and its files", %{
      author: author,
      user: user
    } do
      asset = stored!(%{kind: :video, ext: "webm"}, poster: true, content: "webm bytes")
      validated_import_with!(asset)

      assert Media.delete_asset(author, asset.id) == :ok
      refute Repo.get(Asset, asset.id)
      refute File.exists?(Store.path(asset.sha256, "webm"))
      refute File.exists?(Store.path(asset.poster_sha256, "webp"))

      assert [%AuditEvent{} = event] =
               Repo.all(from e in AuditEvent, where: e.action == "media.deleted")

      assert event.subject_id == asset.id
      assert event.actor_id == user.id
      assert event.details == %{"kind" => "video"}
    end

    test "a deletion keeps a stored file that another asset names as delivery file or poster", %{
      author: author
    } do
      shared = stored!(%{}, poster: true)
      same_delivery = MediaFixtures.insert_asset!(%{sha256: shared.sha256})
      same_poster = MediaFixtures.insert_asset!(%{poster_sha256: shared.poster_sha256})

      assert Media.delete_asset(author, shared.id) == :ok
      assert File.exists?(Store.path(shared.sha256, "svg"))
      assert File.exists?(Store.path(shared.poster_sha256, "webp"))

      assert Media.delete_asset(author, same_delivery.id) == :ok
      refute File.exists?(Store.path(shared.sha256, "svg"))
      assert File.exists?(Store.path(shared.poster_sha256, "webp"))

      assert Media.delete_asset(author, same_poster.id) == :ok
      refute File.exists?(Store.path(shared.poster_sha256, "webp"))
    end

    test "a deletion removes the incoming file of a queued asset", %{author: author} do
      assert {:ok, asset, :created} =
               Media.ingest(author, upload!("a.vtt", MediaFixtures.vtt()))

      assert Media.delete_asset(author, asset.id) == :ok
      assert incoming_names() == []
    end

    test "delete_asset/2 answers forbidden without the role and not_found for an unknown id", %{
      author: author,
      learner: learner
    } do
      asset = stored!()
      assert Media.delete_asset(learner, asset.id) == {:error, :forbidden}
      assert Media.delete_asset(author, Ecto.UUID.generate()) == {:error, :not_found}
      assert Media.delete_asset(author, "not-a-uuid") == {:error, :not_found}
      assert Repo.get(Asset, asset.id)
    end
  end

  ## Library

  describe "list_assets/2" do
    defp at(minutes), do: DateTime.add(~U[2026-10-01 10:00:00Z], minutes * 60, :second)

    test "lists newest first and filters by kind and status", %{author: author} do
      old = MediaFixtures.insert_asset!(%{kind: :image, ext: "webp", inserted_at: at(0)})
      failed = MediaFixtures.insert_asset!(%{status: :failed, sha256: nil, inserted_at: at(1)})
      video = MediaFixtures.insert_asset!(%{kind: :video, ext: "webm", inserted_at: at(2)})

      assert {:ok, %{items: items, next: nil}} = Media.list_assets(author, %{})
      assert Enum.map(items, & &1.id) == [video.id, failed.id, old.id]

      assert {:ok, %{items: [%{id: id}]}} = Media.list_assets(author, %{kind: :image})
      assert id == old.id
      assert {:ok, %{items: [%{id: ^id}]}} = Media.list_assets(author, %{kind: "image"})

      assert {:ok, %{items: [%{id: failed_id}]}} = Media.list_assets(author, %{status: "failed"})
      assert failed_id == failed.id

      assert {:ok, %{items: []}} = Media.list_assets(author, %{kind: :video, status: :failed})
    end

    test "q matches a case-insensitive part of the title with % and _ taken literally", %{
      author: author
    } do
      percent = MediaFixtures.insert_asset!(%{title: "100% Sure", inserted_at: at(0)})
      plain = MediaFixtures.insert_asset!(%{title: "100 percent", inserted_at: at(1)})
      underscore = MediaFixtures.insert_asset!(%{title: "a_b chart", inserted_at: at(2)})
      other = MediaFixtures.insert_asset!(%{title: "axb chart", inserted_at: at(3)})
      backslash = MediaFixtures.insert_asset!(%{title: "c:\\path", inserted_at: at(4)})

      ids = fn filters ->
        {:ok, %{items: items}} = Media.list_assets(author, filters)
        Enum.map(items, & &1.id)
      end

      assert ids.(%{q: "%"}) == [percent.id]
      assert ids.(%{q: "_"}) == [underscore.id]
      assert ids.(%{q: "sure"}) == [percent.id]
      assert ids.(%{q: "CHART"}) == [other.id, underscore.id]
      assert ids.(%{q: "100"}) == [plain.id, percent.id]
      assert ids.(%{q: "\\"}) == [backslash.id]
    end

    test "unused leaves out the assets of programs, drafts and validated imports", %{
      author: author
    } do
      {_program, in_program} = demo_asset!("media/release-checks.svg")
      in_draft = stored!()
      draft_with!(in_draft, "Draft", "media/chart.svg")
      in_import = stored!()
      validated_import_with!(in_import)
      unused = stored!()

      published_import =
        Repo.insert!(%PackImport{
          pack_key: "old-pack",
          pack_version: "1.0.0",
          status: :published,
          report: %{},
          payload: %{},
          media_asset_ids: [unused.id]
        })

      assert published_import.status == :published

      assert {:ok, %{items: items}} = Media.list_assets(author, %{unused: true})
      ids = Enum.map(items, & &1.id)
      assert unused.id in ids
      refute in_program.id in ids
      refute in_draft.id in ids
      refute in_import.id in ids

      assert {:ok, %{items: all}} = Media.list_assets(author, %{unused: false})
      assert in_program.id in Enum.map(all, & &1.id)
    end

    test "limit and the after cursor page through the assets newest first", %{author: author} do
      # Two assets share one second; the id orders them.
      assets =
        for minutes <- [0, 1, 2, 2, 3] do
          MediaFixtures.insert_asset!(%{inserted_at: at(minutes)})
        end

      expected =
        assets
        |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at), &1.id}, :desc)
        |> Enum.map(& &1.id)

      pages =
        Stream.unfold(:start, fn
          nil ->
            nil

          cursor ->
            filters = if cursor == :start, do: %{limit: 2}, else: %{limit: 2, after: cursor}
            {:ok, %{items: items, next: next}} = Media.list_assets(author, filters)
            {Enum.map(items, & &1.id), next}
        end)
        |> Enum.to_list()

      assert pages == Enum.chunk_every(expected, 2)

      assert {:ok, %{items: items}} = Media.list_assets(author, %{})
      assert length(items) == 5
    end

    test "an invalid cursor answers validation_failed and a learner forbidden", %{
      author: author,
      learner: learner
    } do
      for cursor <- [
            "not a cursor",
            Base.url_encode64("no separator", padding: false),
            Base.url_encode64("2026-10-01T10:00:00Z|not-a-uuid", padding: false),
            Base.url_encode64("yesterday|#{Ecto.UUID.generate()}", padding: false)
          ] do
        assert Media.list_assets(author, %{after: cursor}) ==
                 {:error, {:validation_failed, "after", "invalid"}}
      end

      assert Media.list_assets(learner, %{}) == {:error, :forbidden}
    end
  end

  describe "get_asset/2 and update_asset/3" do
    test "get_asset/2 returns the asset with its uses", %{author: author} do
      asset = stored!()
      draft = draft_with!(asset, "Draft", "media/chart.svg")

      assert {:ok, %Asset{id: id}, %{programs: [], drafts: [%{id: draft_id}], imports: []}} =
               Media.get_asset(author, asset.id)

      assert id == asset.id
      assert draft_id == draft.id
    end

    test "get_asset/2 answers not_found for an unknown id and forbidden without the role", %{
      author: author,
      learner: learner
    } do
      asset = stored!()
      assert Media.get_asset(author, Ecto.UUID.generate()) == {:error, :not_found}
      assert Media.get_asset(author, "nope") == {:error, :not_found}
      assert Media.get_asset(learner, asset.id) == {:error, :forbidden}
    end

    test "update_asset/3 changes the title only, within 1 to 255 characters without U+0000", %{
      author: author,
      learner: learner
    } do
      asset = stored!()

      assert {:ok, %Asset{title: "Release checks"} = updated} =
               Media.update_asset(author, asset.id, %{
                 "title" => "Release checks",
                 "status" => "failed",
                 "origin" => "upload",
                 "sha256" => MediaFixtures.random_sha256(),
                 "created_by_id" => Ecto.UUID.generate()
               })

      assert %Asset{status: :ready, origin: :pack, created_by_id: nil} = updated
      assert updated.sha256 == asset.sha256

      for title <- ["", String.duplicate("a", 256), "nul\0title"] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Media.update_asset(author, asset.id, %{"title" => title})

        assert %{title: [_message]} = errors_on(changeset)
      end

      assert {:ok, %Asset{}} =
               Media.update_asset(author, asset.id, %{"title" => String.duplicate("ä", 255)})

      assert Media.update_asset(learner, asset.id, %{"title" => "x"}) == {:error, :forbidden}

      assert Media.update_asset(author, Ecto.UUID.generate(), %{"title" => "x"}) ==
               {:error, :not_found}
    end
  end

  describe "servable/3" do
    test "an author reads every ready file with its extension, and its poster as webp", %{
      author: author
    } do
      asset = stored!(%{}, poster: true)
      queued = MediaFixtures.insert_asset!(%{status: :queued})

      assert Media.servable(author, asset.sha256, "svg")
      refute Media.servable(author, asset.sha256, "webp")
      assert Media.servable(author, asset.poster_sha256, "webp")
      refute Media.servable(author, asset.poster_sha256, "svg")
      refute Media.servable(author, queued.sha256, "svg")
      refute Media.servable(author, MediaFixtures.random_sha256(), "svg")
      refute Media.servable(nil, asset.sha256, "svg")
    end

    test "a learner reads only the files of a published program", %{learner: learner} do
      unused = stored!()
      refute Media.servable(learner, unused.sha256, "svg")

      {program, assets} = publish_demo!()
      asset = assets["media/release-checks.svg"]
      assert Media.servable(learner, asset.sha256, "svg")
      refute Media.servable(learner, asset.sha256, "webp")

      poster = MediaFixtures.random_sha256()
      video = assets["media/assistant-demo.webm"]
      Repo.update_all(from(a in Asset, where: a.id == ^video.id), set: [poster_sha256: poster])
      assert Media.servable(learner, poster, "webp")

      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :archived])
      refute Media.servable(learner, asset.sha256, "svg")
      refute Media.servable(learner, poster, "webp")
    end

    test "a file whose asset is not ready is served to nobody", %{
      author: author,
      learner: learner
    } do
      {_program, asset} = demo_asset!("media/release-checks.svg")
      Repo.update_all(from(a in Asset, where: a.id == ^asset.id), set: [status: :processing])

      refute Media.servable(author, asset.sha256, "svg")
      refute Media.servable(learner, asset.sha256, "svg")
    end
  end

  ## Exceptions, posters, hits, restarts, rebuilt sizes and uses

  describe "an exception of the ingest transaction" do
    # A trigger that refuses every asset row of `operation` (INSERT or
    # UPDATE). The SQL sandbox rolls the function and the trigger back with
    # the test.
    defp refuse_asset_rows!(operation) do
      Repo.query!("""
      CREATE FUNCTION refuse_media_asset() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'media_assets refused by the test';
      END
      $$
      """)

      Repo.query!("""
      CREATE TRIGGER refuse_media_asset BEFORE #{operation} ON media_assets
      FOR EACH ROW EXECUTE FUNCTION refuse_media_asset()
      """)
    end

    test "removes the placed copy and stores no row", %{author: author} do
      refuse_asset_rows!("INSERT")
      upload = upload!("a.vtt", MediaFixtures.vtt("refused"))
      file = pack_file!("media/b.vtt", MediaFixtures.vtt("refused pack file"))

      assert_raise Postgrex.Error, ~r/refused by the test/, fn -> Media.ingest(author, upload) end

      assert_raise Postgrex.Error, ~r/refused by the test/, fn ->
        Media.ingest_pack_file(file, nil)
      end

      refute File.exists?(upload.path)
      assert File.exists?(file.path)
      assert incoming_names() == []
      assert asset_count() == 0
    end

    test "removes the placed copy of a restart and keeps the failed asset", %{author: author} do
      content = MediaFixtures.vtt("restart refused")

      failed =
        MediaFixtures.insert_asset!(%{
          kind: :captions,
          status: :failed,
          failure: :conversion_failed,
          source_sha256: sha256(content),
          sha256: nil,
          ext: nil,
          bytes: nil,
          progress: 0
        })

      refuse_asset_rows!("UPDATE")
      upload = upload!("a.vtt", content)
      file = pack_file!("media/a.vtt", content)

      assert_raise Postgrex.Error, ~r/refused by the test/, fn -> Media.ingest(author, upload) end

      assert_raise Postgrex.Error, ~r/refused by the test/, fn ->
        Media.ingest_pack_file(file, nil)
      end

      refute File.exists?(upload.path)
      assert File.exists?(file.path)
      assert incoming_names() == []

      assert %Asset{status: :failed, failure: :conversion_failed, incoming_bytes: 0} =
               Repo.get!(Asset, failed.id)
    end
  end

  describe "the quota of the ready transition with a poster" do
    alias Espalier.Media.WebpAnim

    defp webp_chunk(fourcc, payload) do
      pad = if rem(byte_size(payload), 2) == 1, do: <<0>>, else: <<>>
      fourcc <> <<byte_size(payload)::little-32>> <> payload <> pad
    end

    # An animated WebP of 4 by 4 pixels with two full frames whose
    # bitstreams hold no more than their VP8L header, which the structural
    # path of Espalier.Media.WebpAnim reads alone; its poster is the first
    # frame.
    defp animated_webp do
      vp8l = webp_chunk("VP8L", <<0x2F, 3 + 3 * 16_384::little-32, 0, 0, 0>>)

      frame =
        webp_chunk(
          "ANMF",
          <<0::24, 0::24, 3::little-24, 3::little-24, 100::little-24, 0>> <> vp8l
        )

      body =
        "WEBP" <>
          webp_chunk("VP8X", <<0x02, 0, 0, 0, 3::little-24, 3::little-24>>) <>
          webp_chunk("ANIM", <<255, 255, 255, 255, 0, 0>>) <> frame <> frame

      "RIFF" <> <<byte_size(body)::little-32>> <> body
    end

    test "a delivery file that fits while the delivery file and its poster do not fails with storage_full and stores neither" do
      MediaFixtures.put_media_env!(storage_max_gb: 1)
      source = animated_webp()

      assert {:ok, %{webp: delivery, poster: poster}} = WebpAnim.check(source)
      assert byte_size(poster) > 0

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.webp", source), nil)

      # The store then holds one byte more than the quota with the poster,
      # and as many bytes as the poster less one below it without.
      others = Media.used_bytes() - byte_size(source)
      filler = @gib + 1 - others - byte_size(delivery) - byte_size(poster)
      assert others + filler + byte_size(delivery) <= @gib
      MediaFixtures.insert_asset!(%{bytes: filler})

      assert %Asset{
               status: :failed,
               failure: :storage_full,
               incoming_bytes: 0,
               sha256: nil,
               bytes: nil,
               poster_sha256: nil,
               poster_bytes: nil
             } = Media.process_now(asset)

      refute File.exists?(Store.path(sha256(delivery), "webp"))
      refute File.exists?(Store.path(sha256(poster), "webp"))
      assert stored_files() == []
      refute File.exists?(Store.incoming_path(asset.id))
    end
  end

  describe "updated_at on a hit of a pack file" do
    test "a pack file that hits a ready asset of origin pack renews updated_at and keeps the origin" do
      # A hit on the source digest.
      content = MediaFixtures.vtt("renewed by an import")

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

      assert %Asset{status: :ready, origin: :pack} = Media.process_now(asset)
      old = set_updated_at!(asset, an_hour_ago())

      assert {:ok, existing, :existing} =
               Media.ingest_pack_file(pack_file!("media/again.vtt", content), nil)

      assert existing.id == asset.id
      assert existing.origin == :pack
      assert DateTime.compare(existing.updated_at, old.updated_at) == :gt
      assert %Asset{origin: :pack, updated_at: stored} = Repo.get!(Asset, asset.id)
      assert DateTime.compare(stored, old.updated_at) == :gt

      # A hit on the digest of a delivery file.
      delivered = MediaFixtures.vtt("delivered by an export")
      file = pack_file!("media/delivered.vtt", delivered)
      ready = MediaFixtures.stored_asset!(file.path, :captions, "vtt", %{duration_ms: 1500})
      old = set_updated_at!(ready, an_hour_ago())

      assert {:ok, existing, :existing} =
               Media.ingest_pack_file(pack_file!("media/exported.vtt", delivered), nil)

      assert existing.id == ready.id
      assert existing.origin == :pack
      assert %Asset{origin: :pack, updated_at: stored} = Repo.get!(Asset, ready.id)
      assert DateTime.compare(stored, old.updated_at) == :gt
      assert incoming_names() == []
    end
  end

  describe "the restart of a failed asset" do
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

    test "an ingest with an actor makes that actor the uploader, so the scan names the person whose copy it reads",
         %{socket_dir: socket_dir, author: first_author, user: first_user} do
      socket = fake_clamd(socket_dir, fn _content -> "stream: Win.Test.EICAR_HDB-1 FOUND\0" end)
      MediaFixtures.put_media_env!(clamav_socket: socket)
      ref = attach_security_events()
      content = MediaFixtures.vtt("infected")

      second_user = user_fixture()
      second_author = %{Scope.for_user(second_user) | roles: [:learner, :author]}
      importer = user_fixture()

      assert {:ok, asset, :created} = Media.ingest(first_author, upload!("a.vtt", content))
      assert %Asset{failure: :malware_found} = Media.process_now(asset)
      first_id = first_user.id
      assert_received {^ref, %{name: :upload_validation, user_id: ^first_id}}

      # An upload of the second author restarts the asset.
      assert {:ok, retried, :existing} = Media.ingest(second_author, upload!("b.vtt", content))
      assert retried.id == asset.id
      assert retried.created_by_id == second_user.id
      assert Repo.get!(Asset, asset.id).created_by_id == second_user.id

      assert [first_event, second_event] =
               Repo.all(
                 from e in AuditEvent,
                   where: e.action == "media.uploaded",
                   order_by: [asc: e.inserted_at, asc: e.id]
               )
               |> Enum.sort_by(&(&1.actor_id != first_user.id))

      assert first_event.actor_id == first_user.id
      assert second_event.actor_id == second_user.id
      assert second_event.subject_id == asset.id
      assert second_event.details == %{"kind" => "captions"}

      assert %Asset{failure: :malware_found} = Media.process_now(asset)
      second_id = second_user.id
      assert_received {^ref, %{name: :upload_validation, user_id: ^second_id}}

      # An import by an author restarts it as well and writes no audit event.
      assert {:ok, _asset, :existing} =
               Media.ingest_pack_file(pack_file!("media/c.vtt", content), importer.id)

      assert Repo.get!(Asset, asset.id).created_by_id == importer.id
      assert %Asset{failure: :malware_found} = Media.process_now(asset)
      importer_id = importer.id
      assert_received {^ref, %{name: :upload_validation, user_id: ^importer_id}}

      # An import without an actor keeps the uploader.
      assert {:ok, _asset, :existing} =
               Media.ingest_pack_file(pack_file!("media/d.vtt", content), nil)

      assert Repo.get!(Asset, asset.id).created_by_id == importer.id
      assert %Asset{failure: :malware_found} = Media.process_now(asset)
      assert_received {^ref, %{name: :upload_validation, user_id: ^importer_id}}

      assert Repo.aggregate(from(e in AuditEvent, where: e.action == "media.uploaded"), :count) ==
               2
    end
  end

  describe "an SVG whose rebuilt file exceeds svg_max_bytes" do
    test "fails with invalid_svg and too_large, and passes at the limit" do
      LogForwarder.attach()
      source = MediaFixtures.growing_svg(1000)
      {:ok, delivery, _facts} = Svg.sanitize(source)
      assert byte_size(delivery) > byte_size(source)

      # The source fits the limit, its rebuilt file does not.
      MediaFixtures.put_media_env!(svg_max_bytes: byte_size(delivery) - 1)

      assert {:ok, asset, :created} =
               Media.ingest_pack_file(pack_file!("media/a.svg", source), nil)

      assert %Asset{
               status: :failed,
               failure: :invalid_svg,
               failure_detail: :too_large,
               incoming_bytes: 0,
               sha256: nil
             } = Media.process_now(asset)

      id = asset.id
      message = "media asset #{id} failed: invalid_svg (too_large)"
      assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}
      assert stored_files() == []

      # At the limit the same file converts.
      MediaFixtures.put_media_env!(svg_max_bytes: byte_size(delivery))

      assert {:ok, %Asset{id: ^id}, :existing} =
               Media.ingest_pack_file(pack_file!("media/a.svg", source), nil)

      assert %Asset{status: :ready, bytes: bytes} = ready = Media.process_now(asset)
      assert bytes == byte_size(delivery)
      assert File.read!(Store.path(ready.sha256, "svg")) == delivery
    end
  end

  describe "the uses of an asset in validated imports" do
    # Runs `fun` and returns the SQL and the parameters of every query of
    # this process that reads pack_imports.
    defp pack_import_queries(fun) do
      test = self()
      ref = make_ref()
      id = "pack-import-queries-#{inspect(ref)}"

      :telemetry.attach(
        id,
        [:espalier, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test and metadata.query =~ "pack_imports",
            do: send(test, {ref, metadata.query, metadata.params})
        end,
        nil
      )

      try do
        fun.()
      after
        :telemetry.detach(id)
      end

      collect_queries(ref, [])
    end

    defp collect_queries(ref, queries) do
      receive do
        {^ref, sql, params} -> collect_queries(ref, [{sql, params} | queries])
      after
        0 -> Enum.reverse(queries)
      end
    end

    test "uses/1 and the unused filter read media_asset_ids through its GIN index", %{
      author: author
    } do
      in_import = stored!()
      validated_import_with!(in_import)
      unused = stored!()

      queries =
        pack_import_queries(fn ->
          assert %{imports: [_import]} = Media.uses(in_import)
          assert %{imports: []} = Media.uses(unused)
          assert {:ok, %{items: [%Asset{id: id}]}} = Media.list_assets(author, %{unused: true})
          assert id == unused.id
        end)

      assert length(queries) == 3

      # Without a sequential scan, the plan shows whether the condition can
      # use the index at all; `= ANY(media_asset_ids)` cannot.
      Repo.query!("SET LOCAL enable_seqscan = off")

      for {sql, params} <- queries do
        plan =
          ("EXPLAIN " <> sql)
          |> Repo.query!(params)
          |> Map.fetch!(:rows)
          |> Enum.map_join("\n", &hd/1)

        assert plan =~ "pack_imports_media_asset_ids_index", plan
      end
    end
  end
end

defmodule Espalier.MediaQuotaConcurrencyTest do
  @moduledoc """
  Task 0018, steps 4 and 8 (ASVS 2.3.2): the storage quota holds under
  concurrent ingests and under concurrent ready transitions, because both
  count and write under the transaction-scoped advisory lock
  `hashtext('espalier.media')`.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock wait. As in `Espalier.Workbench.ConcurrencyTest`,
  each transaction runs on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, the rows are committed and
  deleted again on exit, and the module is synchronous, so no sandboxed
  test sees them. A third transaction holds the quota lock until the
  database reports both contenders waiting on a lock, which makes the race
  certain.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Accounts.{Scope, User}
  alias Espalier.AccountsFixtures
  alias Espalier.Audit.AuditEvent
  alias Espalier.Media
  alias Espalier.Media.{Asset, Store, Svg}
  alias Espalier.MediaFixtures
  alias Espalier.Repo

  @wait_ms 10_000
  @gib 1024 * 1_048_576

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  # Runs `fun` in a transaction of its own in a task outside the sandbox.
  defp transact_async(fun), do: Task.async(fn -> unboxed(fn -> Repo.transact(fun) end) end)

  defp lock_quota(parent) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('espalier.media'))")
    send(parent, :held)

    receive do
      :release -> {:ok, :released}
    end
  end

  setup do
    MediaFixtures.media_env!(storage_max_gb: 1)
    user = unboxed(fn -> AccountsFixtures.user_fixture() end)
    on_exit(fn -> unboxed(fn -> delete_rows!(user) end) end)
    %{user: user, scope: %{Scope.for_user(user) | roles: [:learner, :author]}}
  end

  # Every asset of these tests carries the test user in created_by_id.
  defp delete_rows!(user) do
    ids = Repo.all(from a in Asset, where: a.created_by_id == ^user.id, select: a.id)
    Repo.delete_all(from j in Oban.Job, where: fragment("?->>'asset_id'", j.args) in ^ids)

    Repo.delete_all(
      from e in AuditEvent,
        where: e.subject_id in ^ids or e.subject_id == ^user.id or e.actor_id == ^user.id
    )

    Repo.delete_all(from a in Asset, where: a.id in ^ids)
    Repo.delete_all(from u in User, where: u.id == ^user.id)
  end

  defp file!(name, content) do
    dir = Path.join(Store.uploads_root(), "plug-test")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{System.unique_integer([:positive])}-#{Path.basename(name)}")
    File.write!(path, content)
    %{path: path, file_name: name}
  end

  defp sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  # Holds the quota lock in a transaction of its own until release/1.
  defp hold_quota do
    parent = self()

    holder = transact_async(fn -> lock_quota(parent) end)

    assert_receive :held, @wait_ms
    holder
  end

  defp release(holder) do
    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder, @wait_ms)
  end

  defp concurrently(fun), do: Task.async(fn -> unboxed(fun) end)

  # Waits until `count` backends of this database wait on a lock.
  defp await_waiting(count, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @wait_ms

    %{rows: [[waiting]]} =
      unboxed(fn ->
        Repo.query!("""
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock'
          AND pid <> pg_backend_pid()
        """)
      end)

    cond do
      waiting >= count ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("#{waiting} of #{count} transactions wait on a lock after #{@wait_ms} ms")

      true ->
        Process.sleep(20)
        await_waiting(count, deadline)
    end
  end

  defp incoming_names do
    case File.ls(Store.incoming_root()) do
      {:ok, names} -> names
      {:error, :enoent} -> []
    end
  end

  test "two concurrent ingests with room for one give one asset and one storage_full", %{
    scope: scope,
    user: user
  } do
    first = MediaFixtures.vtt("first upload")
    second = MediaFixtures.vtt("other upload")
    assert byte_size(first) == byte_size(second)

    used = unboxed(&Media.used_bytes/0)

    unboxed(fn ->
      MediaFixtures.insert_asset!(%{
        bytes: @gib - used - byte_size(first),
        created_by_id: user.id
      })
    end)

    uploads = [file!("first.vtt", first), file!("second.vtt", second)]
    holder = hold_quota()

    tasks =
      Enum.map(uploads, fn upload -> concurrently(fn -> Media.ingest(scope, upload) end) end)

    await_waiting(2)
    release(holder)

    results = Enum.map(tasks, &Task.await(&1, @wait_ms))
    assert [{:ok, %Asset{} = asset, :created}] = Enum.filter(results, &match?({:ok, _, _}, &1))
    assert Enum.filter(results, &match?({:error, _}, &1)) == [{:error, :storage_full}]

    # Only the copy of the winner stays, and only the winner has a row and a job.
    assert incoming_names() == [asset.id]

    assert unboxed(fn ->
             Repo.all(
               from a in Asset,
                 where: a.created_by_id == ^user.id and a.status == :queued,
                 select: a.id
             )
           end) == [asset.id]

    assert unboxed(fn -> Media.used_bytes() end) == @gib
  end

  test "two concurrent conversions whose outputs exceed the quota give one ready asset and one storage_full",
       %{user: user} do
    sources = [MediaFixtures.growing_svg(1000, "a"), MediaFixtures.growing_svg(1000, "b")]
    deliveries = Enum.map(sources, fn source -> elem(Svg.sanitize(source), 1) end)
    [in_bytes, in_bytes] = Enum.map(sources, &byte_size/1)
    [out_bytes, out_bytes] = Enum.map(deliveries, &byte_size/1)
    assert out_bytes > in_bytes

    assets =
      unboxed(fn ->
        for {source, n} <- Enum.with_index(sources) do
          {:ok, asset, :created} =
            Media.ingest_pack_file(file!("media/chart-#{n}.svg", source), user.id)

          asset
        end
      end)

    # The first ready transition fits exactly; the second one exceeds the
    # quota by its growth.
    used = unboxed(&Media.used_bytes/0)

    unboxed(fn ->
      MediaFixtures.insert_asset!(%{
        bytes: @gib - used - (out_bytes - in_bytes),
        created_by_id: user.id
      })
    end)

    holder = hold_quota()
    tasks = Enum.map(assets, fn asset -> concurrently(fn -> Media.process(asset.id) end) end)
    await_waiting(2)
    release(holder)
    assert Enum.map(tasks, &Task.await(&1, @wait_ms)) == [:ok, :ok]

    ended = unboxed(fn -> Enum.map(assets, &Repo.get!(Asset, &1.id)) end)
    assert [%Asset{status: :ready} = winner] = Enum.filter(ended, &(&1.status == :ready))

    assert [%Asset{failure: :storage_full, incoming_bytes: 0, sha256: nil, bytes: nil} = loser] =
             Enum.filter(ended, &(&1.status == :failed))

    {winner_delivery, loser_delivery} =
      if winner.id == hd(assets).id,
        do: List.to_tuple(deliveries),
        else: deliveries |> Enum.reverse() |> List.to_tuple()

    assert winner.sha256 == sha256(winner_delivery)
    assert File.read!(Store.path(winner.sha256, "svg")) == winner_delivery
    refute File.exists?(Store.path(sha256(loser_delivery), "svg"))

    assert Path.wildcard(Path.join(Store.files_root(), "**/*.svg")) == [
             Store.path(winner.sha256, "svg")
           ]

    assert incoming_names() == []
    assert MediaFixtures.work_dirs(winner.id) == []
    assert MediaFixtures.work_dirs(loser.id) == []
    # The winner counts its delivery file, the loser nothing.
    assert unboxed(fn -> Media.used_bytes() end) == @gib - in_bytes
  end
end
