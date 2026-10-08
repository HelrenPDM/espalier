defmodule EspalierWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  Every error renders `{"error": code}` without internals (README section
  6.10). See config/config.exs.
  """

  @codes %{
    400 => "bad_request",
    401 => "unauthenticated",
    403 => "forbidden",
    404 => "not_found",
    429 => "rate_limited",
    500 => "internal_error"
  }

  def render(template, _assigns) do
    status = template |> String.split(".") |> hd() |> String.to_integer()
    %{error: code(status)}
  rescue
    ArgumentError -> %{error: "internal_error"}
  end

  defp code(status) when is_map_key(@codes, status), do: Map.fetch!(@codes, status)
  defp code(status) when status in 400..499, do: "bad_request"
  defp code(_status), do: "internal_error"
end
