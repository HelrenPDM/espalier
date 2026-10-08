defmodule EspalierWeb.EnumerationTimingTest do
  # Runs with the production Argon2 parameters: mix test --only timing.
  use EspalierWeb.ConnCase, async: false

  @moduletag :timing
  @moduletag timeout: :timer.minutes(5)

  setup do
    previous = Application.get_all_env(:argon2_elixir)
    Application.put_env(:argon2_elixir, :t_cost, 2)
    Application.put_env(:argon2_elixir, :m_cost, 16)

    on_exit(fn ->
      for {key, value} <- previous, do: Application.put_env(:argon2_elixir, key, value)
    end)
  end

  defp timed_sign_in(email) do
    conn = with_csrf_token(api_conn())
    started = System.monotonic_time(:microsecond)

    conn =
      post(conn, "/api/auth/password", %{email: email, password: "a wrong but long password"})

    elapsed = System.monotonic_time(:microsecond) - started
    {conn, elapsed}
  end

  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end

  test "known and unknown addresses take the same time and get the same answer" do
    known = for _ <- 1..20, do: user_fixture().email
    unknown = for _ <- 1..20, do: unique_user_email()

    results =
      known
      |> Enum.zip(unknown)
      |> Enum.flat_map(fn {k, u} ->
        [{:known, timed_sign_in(k)}, {:unknown, timed_sign_in(u)}]
      end)

    for {_group, {conn, _elapsed}} <- results do
      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
    end

    medians =
      results
      |> Enum.group_by(fn {group, _} -> group end, fn {_, {_conn, elapsed}} -> elapsed end)
      |> Map.new(fn {group, times} -> {group, median(times)} end)

    difference = abs(medians.known - medians.unknown) / max(medians.known, medians.unknown)

    assert difference < 0.25,
           "medians #{inspect(medians)} differ by #{Float.round(difference * 100, 1)} %"
  end
end
