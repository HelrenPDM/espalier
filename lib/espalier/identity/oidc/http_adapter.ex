defmodule Espalier.Identity.Oidc.HttpAdapter do
  @moduledoc """
  The HTTP transport of every request to an OIDC provider (ASVS 15.3.2).

  It uses Req without following redirects, so discovery, JWKS, token and
  pushed authorization requests fail on redirect responses. Req verifies TLS
  certificates by default.
  """
  @behaviour :oidcc_http_adapter

  @impl :oidcc_http_adapter
  def request(method, request, http_options, _request_options, _config) do
    {url, headers, body} = request_parts(request)

    options = [
      method: method,
      url: to_string(url),
      headers: headers,
      body: body,
      redirect: false,
      retry: false,
      raw: true,
      decode_body: false,
      compressed: false,
      connect_options: [transport_opts: [verify: :verify_peer]]
    ]

    options =
      case Keyword.fetch(http_options, :timeout) do
        {:ok, timeout} ->
          Keyword.put(options, :receive_timeout, timeout)
          |> Keyword.update!(:connect_options, &Keyword.put(&1, :timeout, timeout))

        :error ->
          options
      end

    case Req.request(options) do
      {:ok, response} ->
        headers =
          response
          |> Req.get_headers_list()
          |> Enum.map(fn {name, value} -> {String.to_charlist(name), value} end)

        {:ok,
         {{"HTTP/1.1", response.status, ""}, headers, IO.iodata_to_binary(response.body || "")}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_parts({url, headers}) do
    {url, headers(headers), nil}
  end

  defp request_parts({url, headers, content_type, body}) do
    headers = headers(headers)

    headers =
      [{"content-type", to_string(content_type)}
       | Enum.reject(headers, &(elem(&1, 0) == "content-type"))]

    {url, headers, body(body)}
  end

  defp headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), IO.iodata_to_binary(value)}
    end)
  end

  defp body({:chunkify, producer, accumulator}) when is_function(producer, 1),
    do: collect_body(producer, accumulator, [])

  defp body({producer, accumulator}) when is_function(producer, 1),
    do: collect_body(producer, accumulator, [])

  defp body(body), do: IO.iodata_to_binary(body)

  defp collect_body(producer, accumulator, chunks) do
    case producer.(accumulator) do
      :eof -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
      {:ok, chunk, next_accumulator} -> collect_body(producer, next_accumulator, [chunk | chunks])
    end
  end
end
