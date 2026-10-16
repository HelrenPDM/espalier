defmodule EspalierWeb.CatalogJSON do
  @moduledoc """
  Catalog views for learners (README section 7, domain rule 4; ASVS
  15.3.1). Every view names its members explicitly. No view carries an
  answer key: no `correct`, `feedback` or `expected` member and no raw
  `config` of an item or a station. Correctness and feedback reach a
  learner only through `Espalier.Learning.Evaluator` in the answer to the
  learner's own submission.

  `Espalier.Catalog` returns only published programs and only rows without
  `archived_at`, so the views render what they receive.

  A `figure` or a `video` block carries `media` (task 0018, step 12),
  resolved from the media of the published program into URLs below
  `/media/`; the other kinds carry `null`. The view names no asset id, no
  source name or digest and no file path of the store. `available` is false
  when an external file or an embed names a host that has left
  `MEDIA_EXTERNAL_HOSTS` or `MEDIA_EMBED_HOSTS` since the publish, or when
  a media file is missing.
  """

  alias Espalier.Catalog.{Block, Citation, CompanionFormat, Item, Lesson, Rule, Station}
  alias Espalier.Media
  alias Espalier.Media.Asset

  @doc "Renders the list of published programs."
  def index(%{programs: programs}) do
    %{programs: Enum.map(programs, &%{slug: &1.slug, title: &1.title, locale: &1.locale})}
  end

  @doc "Renders a program with its stations, segments, modules and formats."
  def show(%{program: program}) do
    %{
      id: program.id,
      slug: program.slug,
      title: program.title,
      locale: program.locale,
      pack_version: program.pack_version,
      stations: Enum.map(program.stations, &station/1),
      segments:
        Enum.map(program.segments, fn segment ->
          %{
            key: segment.key,
            label: segment.label,
            description: segment.description,
            default_path: segment.default_path
          }
        end),
      modules:
        Enum.map(program.modules, fn module ->
          %{
            id: module.id,
            number: module.number,
            title: module.title,
            summary: module.summary,
            phases: module.phases,
            single_path: module.single_path
          }
        end),
      companion_formats: Enum.map(program.companion_formats, &companion_format/1)
    }
  end

  defp station(%Station{config: config} = station) do
    config = config || %{}

    %{
      position: station.position,
      kind: station.kind,
      title: station.title,
      module_id: station.module_id,
      question: string_at(config, "question"),
      intro: string_at(config, "intro"),
      questions: config |> list_at("questions") |> Enum.map(&question/1)
    }
  end

  defp question(question) do
    %{
      key: question["key"],
      kind: question["kind"],
      label: question["label"],
      options: question |> list_at("options") |> Enum.map(&%{key: &1["key"], label: &1["label"]})
    }
  end

  @doc "Renders a companion format (schema `CompanionFormatView`)."
  def companion_format(%CompanionFormat{} = format) do
    %{
      id: format.id,
      key: format.key,
      title: format.title,
      description: format.description,
      phases: format.phases,
      attendance_counts: format.attendance_counts
    }
  end

  @doc """
  Renders a module with its lessons, rules, practice items, exams and
  objectives (the map of `Espalier.Catalog.module_view/1`). `policies` maps
  a policy key to its current version (`Espalier.Policies`), so that a
  block of kind `placeholder` carries the policy text (README section 7,
  domain rule 8).
  """
  def module(%{view: view} = assigns) do
    %{module: module, objective_keys: keys} = view
    policies = Map.get(assigns, :policies, %{})

    %{
      id: module.id,
      program_slug: module.program.slug,
      number: module.number,
      title: module.title,
      summary: module.summary,
      phases: module.phases,
      single_path: module.single_path,
      lessons: Enum.map(view.lessons, &lesson(&1, policies, Map.get(view, :media, %{}))),
      rules: Enum.map(view.rules, &rule/1),
      practice_items: Enum.map(view.practice_items, &item(&1, keys)),
      exams:
        Enum.map(view.exams, fn exam ->
          %{
            id: exam.id,
            key: exam.key,
            title: exam.title,
            max_wrong: exam.max_wrong,
            counts_for_credential: exam.counts_for_credential,
            items: Enum.map(exam.items, &item(&1, keys))
          }
        end),
      objectives: Enum.map(view.objectives, &objective/1)
    }
  end

  defp lesson(%Lesson{} = lesson, policies, media) do
    %{
      id: lesson.id,
      key: lesson.key,
      position: lesson.position,
      title: lesson.title,
      blocks: Enum.map(lesson.blocks, &block(&1, policies, media))
    }
  end

  defp block(%Block{} = block, policies, media) do
    %{
      id: block.id,
      kind: block.kind,
      body: block.body,
      provenance: block.provenance,
      collapsed_on: block.collapsed_on,
      placeholder_key: block.placeholder_key,
      policy: block_policy(block, policies),
      media: block_media(block, media),
      citations: Enum.map(block.citations, &citation/1)
    }
  end

  @doc """
  The media of a `figure` or a `video` block (schema `BlockMedia`), from
  the block attributes and `media`, a map of `media/` path to its asset;
  `nil` for the other kinds.
  """
  def block_media(%Block{kind: :figure, media: %{} = attrs}, media) do
    asset = ready(media, attrs["src"])
    decorative = attrs["decorative"] == true

    %{
      image: image(asset),
      video: nil,
      poster: if(asset && asset.animated, do: poster(nil, asset)),
      embed: nil,
      captions: [],
      alt: if(decorative, do: nil, else: attrs["alt"]),
      decorative: decorative,
      size: attrs["size"] || "full",
      title: nil,
      available: asset != nil
    }
  end

  def block_media(%Block{kind: :video, media: %{} = attrs}, media) do
    {video, embed, available} = video_source(attrs, media)
    file = ready(media, attrs["src"])
    poster_asset = ready(media, attrs["poster"])

    captions =
      for %{"src" => src, "lang" => lang} <- attrs["captions"] || [],
          %Asset{} = asset <- [ready(media, src)],
          do: %{url: Media.url(asset), lang: lang}

    %{
      image: nil,
      video: video,
      poster: if(embed == nil, do: poster(poster_asset, file)),
      embed: embed,
      captions: captions,
      alt: nil,
      decorative: false,
      size: nil,
      title: attrs["title"],
      available: available
    }
  end

  def block_media(%Block{}, _media), do: nil

  defp video_source(%{"embed" => embed}, _media) when is_binary(embed) do
    {nil, %{url: embed, host: url_host(embed)}, allowed?(embed, Media.embed_hosts())}
  end

  defp video_source(%{"src" => "media/" <> _rest = path}, media) do
    case ready(media, path) do
      %Asset{} = asset ->
        video = %{
          url: Media.url(asset),
          mime: "video/webm",
          width: asset.width,
          height: asset.height,
          duration_ms: asset.duration_ms,
          has_audio: asset.has_audio,
          external: false
        }

        {video, nil, true}

      nil ->
        {nil, nil, false}
    end
  end

  defp video_source(%{"src" => src}, _media) when is_binary(src) do
    video = %{
      url: src,
      mime: external_mime(src),
      width: nil,
      height: nil,
      duration_ms: nil,
      has_audio: nil,
      external: true
    }

    {video, nil, allowed?(src, Media.external_hosts())}
  end

  defp video_source(_attrs, _media), do: {nil, nil, false}

  defp external_mime(url) do
    path = url |> URI.parse() |> Map.get(:path) |> to_string() |> String.downcase()

    if String.ends_with?(path, ".mp4"),
      do: "video/mp4",
      else: "video/webm"
  end

  defp ready(media, path) when is_binary(path) do
    case Map.get(media, path) do
      %Asset{status: :ready} = asset -> asset
      _missing -> nil
    end
  end

  defp ready(_media, _path), do: nil

  defp image(nil), do: nil

  defp image(%Asset{} = asset) do
    %{
      url: Media.url(asset),
      mime: Media.mime(asset.ext),
      width: asset.width,
      height: asset.height,
      has_alpha: asset.has_alpha,
      animated: asset.animated
    }
  end

  # A poster attribute names an image asset, and an animated image gives its
  # still first frame, so that nothing moves before the learner starts the
  # video (WCAG 2.2 2.2.2); otherwise a video or an animated image shows its
  # own poster with its own size.
  defp poster(%Asset{animated: true} = image, fallback) do
    case Media.poster_url(image) do
      nil -> poster(nil, fallback)
      url -> %{url: url, width: image.width, height: image.height}
    end
  end

  defp poster(%Asset{} = image, _fallback),
    do: %{url: Media.url(image), width: image.width, height: image.height}

  defp poster(nil, %Asset{poster_sha256: sha256} = asset) when is_binary(sha256),
    do: %{url: Media.poster_url(asset), width: asset.width, height: asset.height}

  defp poster(_image, _fallback), do: nil

  # Host and port as Espalier.Credentials.Webhook compares them: an entry
  # without a port admits the default port of https.
  defp allowed?(url, hosts) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, port: port} when is_binary(host) ->
        host = String.downcase(host)

        Enum.any?(hosts, fn
          {^host, nil} -> port == 443
          {^host, ^port} -> true
          _entry -> false
        end)

      _other ->
        false
    end
  end

  defp url_host(url) do
    case URI.parse(url) do
      %URI{host: host, port: port} when is_binary(host) and port not in [nil, 443] ->
        "#{String.downcase(host)}:#{port}"

      %URI{host: host} when is_binary(host) ->
        String.downcase(host)

      _other ->
        ""
    end
  end

  defp block_policy(%Block{kind: :placeholder, placeholder_key: key}, policies)
       when is_binary(key),
       do: policies |> Map.get(key) |> policy_text()

  defp block_policy(_block, _policies), do: nil

  @doc """
  Renders the current version of a policy (schema `PolicyText`), or `nil`.
  """
  def policy_text(nil), do: nil

  def policy_text(version) do
    %{
      key: version.policy.key,
      number: version.number,
      effective_from: version.effective_from,
      body: version.body
    }
  end

  @doc """
  Returns the placeholder keys of the blocks of a module view, for the
  lookup of their current policy versions.
  """
  def placeholder_keys(%{lessons: lessons}) do
    for lesson <- lessons,
        %Block{kind: :placeholder, placeholder_key: key} <- lesson.blocks,
        is_binary(key),
        uniq: true,
        do: key
  end

  defp rule(%Rule{} = rule) do
    %{
      id: rule.id,
      number: rule.number,
      statement: rule.statement,
      action: rule.action,
      citations: Enum.map(rule.citations, &citation/1)
    }
  end

  defp citation(%Citation{source: source} = citation) do
    %{
      locator: citation.locator,
      source: %{
        key: source.key,
        title: source.title,
        publisher: source.publisher,
        url: source.url,
        edition_date: source.edition_date,
        retrieved_on: source.retrieved_on,
        kind: source.kind
      }
    }
  end

  @doc """
  Renders an item without its answer key (schema `ItemView`). `keys` maps
  item ids to the sorted keys of their live objectives. The lists of the
  other kinds are empty.
  """
  def item(%Item{config: config} = item, keys) do
    config = config || %{}

    %{
      id: item.id,
      key: item.key,
      kind: item.kind,
      stem: item.stem,
      provenance: item.provenance,
      lesson_id: item.lesson_id,
      objective_keys: Map.get(keys, item.id, []),
      options: options(item),
      slots:
        if(item.kind == :slot_builder,
          do:
            config
            |> list_at("slots")
            |> Enum.map(fn slot ->
              %{key: slot["key"], label: slot["label"], options: choices(slot, "options")}
            end),
          else: []
        ),
      cases:
        if(item.kind == :classification,
          do: config |> list_at("cases") |> Enum.map(&%{key: &1["key"], text: &1["text"]}),
          else: []
        ),
      categories: if(item.kind == :classification, do: choices(config, "categories"), else: []),
      checks:
        if(item.kind == :checklist_drill,
          do:
            config
            |> list_at("checks")
            |> Enum.map(&%{key: &1["key"], label: &1["label"], required: &1["required"] == true}),
          else: []
        )
    }
  end

  defp options(%Item{kind: kind, options: options})
       when kind in [:single_choice, :multiple_choice, :poll],
       do: Enum.map(options, &%{key: &1.key, label: &1.label})

  defp options(_item), do: []

  defp choices(map, key),
    do: map |> list_at(key) |> Enum.map(&%{key: &1["key"], label: &1["label"]})

  @doc """
  Renders a learning objective of `Espalier.Catalog.objective_links/2`
  (schema `ObjectiveView`): the evidence items ordered by key, followed by
  the evidence formats ordered by key.
  """
  def objective(%{objective: objective} = link) do
    %{
      key: objective.key,
      statement: objective.statement,
      area: objective.area,
      depth: objective.depth,
      phase: objective.phase,
      domain: objective.domain,
      lesson_ids: link.lesson_ids,
      evidence:
        Enum.map(link.item_ids, &%{kind: "item", id: &1}) ++
          Enum.map(link.format_ids, &%{kind: "format", id: &1})
    }
  end

  @doc "Renders the glossary terms of a program."
  def glossary(%{terms: terms}) do
    %{terms: Enum.map(terms, &%{slug: &1.slug, label: &1.label, short_text: &1.short_text})}
  end

  @doc """
  Renders the handbook: every rule per module, and every placeholder key
  with the current version of its policy (`policies` maps a key to it).
  """
  def handbook(%{handbook: handbook} = assigns) do
    policies = Map.get(assigns, :policies, %{})

    %{
      modules:
        Enum.map(handbook.modules, fn module ->
          %{
            id: module.id,
            number: module.number,
            title: module.title,
            rules:
              Enum.map(
                module.rules,
                &%{number: &1.number, statement: &1.statement, action: &1.action}
              )
          }
        end),
      placeholders:
        Enum.map(
          handbook.placeholders,
          &%{key: &1, policy: policies |> Map.get(&1) |> policy_text()}
        )
    }
  end

  defp string_at(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp list_at(map, key) when is_map(map) do
    case Map.get(map, key) do
      entries when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _other -> []
    end
  end
end
