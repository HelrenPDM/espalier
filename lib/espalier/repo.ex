defmodule Espalier.Repo do
  use Ecto.Repo,
    otp_app: :espalier,
    adapter: Ecto.Adapters.Postgres
end
