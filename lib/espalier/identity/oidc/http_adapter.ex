defmodule Espalier.Identity.Oidc.HttpAdapter do
  @moduledoc """
  The HTTP transport of every request to an OIDC provider (ASVS 15.3.2).

  It calls `:httpc.request/5` as `oidcc_http_adapter_httpc` of oidcc 3.9.0
  does, with the HTTP option `{:autoredirect, false}` added, so discovery,
  JWKS, token and pushed authorization requests follow no redirect. A
  redirect answer reaches oidcc as a non-200 status and fails the request.
  The adapter adds no `ssl` option, so `:httpc` keeps its default TLS
  options.
  """
  @behaviour :oidcc_http_adapter

  @impl :oidcc_http_adapter
  def request(method, request, http_options, request_options, _config) do
    http_options = Keyword.put(http_options, :autoredirect, false)
    :httpc.request(method, request, http_options, request_options, :default)
  end
end
