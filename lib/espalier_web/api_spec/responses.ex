defmodule EspalierWeb.ApiSpec.Responses do
  @moduledoc """
  Error answers and security requirements shared by the operations of
  `EspalierWeb.ApiSpec`. Every error answer has the schema
  `EspalierWeb.Schemas.Error`, and its description names the codes that
  the route returns with that status.
  """

  alias EspalierWeb.Schemas.Error
  alias OpenApiSpex.{Header, Schema}

  @doc """
  Returns the error answers as a map of status to response, from a keyword
  or list of `{status, codes}`. A 429 answer also declares `retry-after`.
  """
  @spec errors([{pos_integer(), [String.t()]}]) :: %{pos_integer() => tuple()}
  def errors(statuses) do
    Map.new(statuses, fn {status, codes} -> {status, error(status, codes)} end)
  end

  defp error(429, codes) do
    {description(codes), "application/json", Error,
     headers: %{
       "retry-after" => %Header{
         description: "Seconds until the bucket admits the next request.",
         schema: %Schema{type: :integer, minimum: 1}
       }
     }}
  end

  defp error(_status, codes), do: {description(codes), "application/json", Error}

  defp description(codes), do: "Error codes: " <> Enum.map_join(codes, ", ", &"`#{&1}`")

  @doc "The requirement of a route behind the session cookie."
  def session, do: [%{"session_cookie" => []}]

  @doc "The requirement of a mutating route behind the session cookie."
  def session_and_csrf, do: [%{"session_cookie" => [], "csrf_header" => []}]

  @doc "The requirement of a mutating route that needs only the CSRF token."
  def csrf, do: [%{"csrf_header" => []}]

  @doc "A route without a requirement."
  def public, do: [%{}]
end
