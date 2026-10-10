defmodule EspalierWeb.ModuleController do
  @moduledoc """
  The module view for signed-in learners: lessons, rules, practice items,
  exams and the learning objectives of the topic, without answer keys. An
  archived module, or a module of a program that is not published, answers
  404.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Catalog
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CatalogJSON
  alias EspalierWeb.Schemas.{Fields, ModuleView}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Catalog"]
  security Responses.session()

  operation :show,
    summary: "Read a module",
    parameters: [
      id: [in: :path, required: true, description: "The module id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{200 => {"The module", "application/json", ModuleView}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{id: id}) do
    with {:ok, view} <- Catalog.module_view(id) do
      json(conn, CatalogJSON.module(%{view: view}))
    end
  end
end
