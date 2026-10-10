defmodule EspalierWeb.ProgramController do
  @moduledoc """
  Catalog reads for signed-in learners: the published programs, a program,
  its glossary and its handbook (README section 8). Programs whose status
  is `draft` or `archived` answer 404.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Catalog
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CatalogJSON
  alias EspalierWeb.Schemas.{Fields, Glossary, Handbook, ProgramList, ProgramView}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Catalog"]
  security Responses.session()

  @slug [
    slug: [
      in: :path,
      required: true,
      description: "The slug of a published program.",
      schema: Fields.key_param("The slug of a published program.")
    ]
  ]

  operation :index,
    summary: "List the published programs",
    responses:
      Map.merge(
        %{200 => {"The published programs", "application/json", ProgramList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]}
        ])
      )

  def index(conn, _params) do
    json(conn, CatalogJSON.index(%{programs: Catalog.list_published_programs()}))
  end

  operation :show,
    summary: "Read a program",
    parameters: @slug,
    responses:
      Map.merge(
        %{200 => {"The program", "application/json", ProgramView}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{slug: slug}) do
    with {:ok, program} <- Catalog.program_view(slug) do
      json(conn, CatalogJSON.show(%{program: program}))
    end
  end

  operation :glossary,
    summary: "Read the glossary of a program",
    parameters: @slug,
    responses:
      Map.merge(
        %{200 => {"The glossary", "application/json", Glossary}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def glossary(conn, %{slug: slug}) do
    with {:ok, terms} <- Catalog.glossary(slug) do
      json(conn, CatalogJSON.glossary(%{terms: terms}))
    end
  end

  operation :handbook,
    summary: "Read the handbook of a program",
    description:
      "Every rule with its statement and action grouped by module, plus the keys of the " <>
        "program's placeholder blocks (README section 7, domain rule 10).",
    parameters: @slug,
    responses:
      Map.merge(
        %{200 => {"The handbook", "application/json", Handbook}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def handbook(conn, %{slug: slug}) do
    with {:ok, handbook} <- Catalog.handbook(slug) do
      json(conn, CatalogJSON.handbook(%{handbook: handbook}))
    end
  end
end
