defmodule EspalierWeb.Plugs.RateLimit do
  @moduledoc """
  Applies an IP bucket of `Espalier.RateLimit` in a controller:

      plug EspalierWeb.Plugs.RateLimit, [bucket: :auth_ip] when action in [:create]

  Account buckets run in the controller after parameter parsing through
  `check_account/3`. A denial answers 429 with `retry-after` and
  `{"error":"rate_limited"}`, and logs `excess_rate_limit_exceeded`.
  """
  @behaviour Plug

  import Plug.Conn

  alias Espalier.RateLimit
  alias Espalier.SecurityLog

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :bucket)

  @impl Plug
  def call(conn, bucket) do
    case RateLimit.check_ip(bucket, conn.remote_ip) do
      {:allow, _count} -> conn
      {:deny, retry_after_ms} -> deny(conn, bucket, retry_after_ms)
    end
  end

  @doc """
  Counts a hit of the normalized `identifier` in the account bucket and
  returns the conn, or the halted 429 answer.
  """
  def check_account(conn, bucket, identifier) when is_binary(identifier) do
    case RateLimit.check_account(bucket, identifier) do
      {:allow, _count} -> conn
      {:deny, retry_after_ms} -> deny(conn, bucket, retry_after_ms)
    end
  end

  defp deny(conn, bucket, retry_after_ms) do
    SecurityLog.event(:excess_rate_limit_exceeded, %{ip: conn.remote_ip, reason: bucket})

    conn
    |> put_resp_header("retry-after", Integer.to_string(max(div(retry_after_ms + 999, 1000), 1)))
    |> put_resp_content_type("application/json")
    |> send_resp(429, ~s({"error":"rate_limited"}))
    |> halt()
  end
end
