defmodule Espalier.ReleaseMediaTest do
  @moduledoc """
  `Espalier.Release.import_pack/2` on a pack with media (task 0018, steps 8
  and 23): the release function starts the application as an eval node
  does, so the job insert of an ingest finds a running Oban instance, and
  processes the media in the calling process before the publish.

  The module runs synchronously, as `Espalier.ReleaseTest` does, because
  the release functions change the application environment, and the real
  ingest takes the advisory lock of the quota.
  """
  use Espalier.DataCase, async: false

  import ExUnit.CaptureIO

  alias Espalier.Catalog.{PackImport, Program, ProgramMedia}
  alias Espalier.{LearningFixtures, MediaFixtures, PackFixtures, Release}
  alias Espalier.Media.{Asset, ProcessWorker}

  setup do
    MediaFixtures.media_env!()
    oban = Application.fetch_env!(:espalier, Oban)
    on_exit(fn -> Application.put_env(:espalier, Oban, oban) end)
    %{pack: PackFixtures.copy_pack!(PackFixtures.demo_path())}
  end

  defp statuses(ids),
    do: Repo.all(from a in Asset, where: a.id in ^ids, select: a.status) |> Enum.uniq()

  test "import_pack/2 ingests, processes and publishes the media of a pack", %{pack: pack} do
    {result, output} = with_io(fn -> Release.import_pack(pack) end)

    assert {:ok, %PackImport{status: :published, media_asset_ids: ids}} = result
    assert output =~ "Published ai-assistant-basics-demo"
    assert length(ids) == 3
    assert statuses(ids) == [:ready]

    program = Repo.get_by!(Program, slug: LearningFixtures.demo_slug())

    assert Repo.all(
             from m in ProgramMedia,
               where: m.program_id == ^program.id,
               order_by: m.path,
               select: m.path
           ) == MediaFixtures.demo_media_paths() |> Enum.sort()
  end

  test "import_pack/2 with draft: true stores the draft and leaves the jobs queued", %{
    pack: pack
  } do
    {result, output} = with_io(fn -> Release.import_pack(pack, draft: true) end)

    assert {:ok, %PackImport{status: :validated, media_asset_ids: ids}} = result
    assert output =~ "as draft import"
    assert statuses(ids) == [:queued]
    for id <- ids, do: assert_enqueued(worker: ProcessWorker, args: %{"asset_id" => id})
  end

  test "import_pack/2 answers media_not_ready for a pack whose media file fails", %{pack: pack} do
    PackFixtures.write!(pack, "media/assistant-demo-en.vtt", MediaFixtures.vtt_with_style())

    {result, output} = with_io(fn -> Release.import_pack(pack) end)

    assert {:error, {:media_not_ready, [%{"path" => "media/assistant-demo-en.vtt"}]}} = result
    assert output =~ "media/assistant-demo-en.vtt: failed"
    refute Repo.get_by(Program, slug: LearningFixtures.demo_slug())
  end
end
