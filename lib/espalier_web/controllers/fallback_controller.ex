defmodule EspalierWeb.FallbackController do
  @moduledoc """
  Translates controller errors into the JSON error body `{"error": code}`
  (README section 6.10). The answers carry a code and no internals.
  """
  use EspalierWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_failed",
      fields: EspalierWeb.ChangesetJSON.error_codes(changeset)
    })
  end

  def call(conn, {:error, :invalid_credentials}),
    do: error(conn, :unauthorized, "invalid_credentials")

  def call(conn, {:error, :invalid_token}), do: error(conn, :bad_request, "invalid_token")
  def call(conn, {:error, :bad_request}), do: error(conn, :bad_request, "bad_request")
  def call(conn, {:error, :forbidden}), do: error(conn, :forbidden, "forbidden")
  def call(conn, {:error, :not_found}), do: error(conn, :not_found, "not_found")

  defp error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: code})
  end
end
