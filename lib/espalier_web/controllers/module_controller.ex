defmodule EspalierWeb.ModuleController do
  @moduledoc """
  The module view for signed-in learners: lessons, rules, practice items,
  exams and the learning objectives of the topic, without answer keys. A
  placeholder block carries the current version of its policy (task 0013). An
  archived module, or a module of a program that is not published, answers
  404.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.{Catalog, Policies}
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
      policies = view |> CatalogJSON.placeholder_keys() |> Policies.current_versions_by_key()
      json(conn, CatalogJSON.module(%{view: view, policies: policies}))
    end
  end
end
