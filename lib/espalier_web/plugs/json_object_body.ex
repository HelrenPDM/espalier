defmodule EspalierWeb.Plugs.JsonObjectBody do
  @moduledoc """
  Answers 422 `{"error":"validation_failed","fields":{"body":["invalid_type"]}}`
  when the request body holds the member `_json` (task 0009).

  `Plug.Parsers` puts a JSON body that is no object under the key `_json`,
  and `OpenApiSpex.Plug.CastAndValidate` 3.22.4 then validates only the
  value under that key and leaves every other member unchecked
  (`OpenApiSpex.Operation2`). Every request schema of the learner routes is
  an object, so a body with `_json`, whether a wrapped array or an object
  with that member, never fits; the plug rejects it before
  `CastAndValidate` runs.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{body_params: %{"_json" => _value}} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(422, ~s({"error":"validation_failed","fields":{"body":["invalid_type"]}}))
    |> halt()
  end

  def call(conn, _opts), do: conn
end
