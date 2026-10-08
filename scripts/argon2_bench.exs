# Benchmarks Argon2id inside the production image (make argon2-bench).
#
# Reads ARGON2_T_COST and ARGON2_M_COST (defaults 2 and 16), prints
# Argon2.Stats.report/1, then verifies one hash 200 times with as many
# concurrent verifications as four times the online schedulers, and prints
# the error count, the median and the 95th percentile. Exits 1 on any error.
# docs/security/authentication.md records the chosen parameters.

t_cost = String.to_integer(System.get_env("ARGON2_T_COST", "2"))
m_cost = String.to_integer(System.get_env("ARGON2_M_COST", "16"))
opts = [t_cost: t_cost, m_cost: m_cost, parallelism: 1, argon2_type: 2]

Argon2.Stats.report(opts)

password = Base.encode64(:crypto.strong_rand_bytes(24))
hash = Argon2.Base.hash_password(password, Argon2.Base.gen_salt(), opts)
runs = 200

results =
  1..runs
  |> Task.async_stream(
    fn _ ->
      started = System.monotonic_time(:microsecond)

      outcome =
        try do
          if Argon2.verify_pass(password, hash), do: :ok, else: :mismatch
        rescue
          error in ArgumentError -> {:error, Exception.message(error)}
        end

      {outcome, System.monotonic_time(:microsecond) - started}
    end,
    max_concurrency: System.schedulers_online() * 4,
    timeout: :infinity
  )
  |> Enum.map(fn {:ok, result} -> result end)

errors = Enum.count(results, fn {outcome, _} -> outcome != :ok end)
times = results |> Enum.map(fn {_, us} -> us end) |> Enum.sort()
percentile = fn p -> Enum.at(times, min(round(p * runs) - 1, runs - 1)) / 1000 end

IO.puts("""
Concurrent verification: #{runs} runs, max_concurrency #{System.schedulers_online() * 4}, \
dirty CPU schedulers #{:erlang.system_info(:dirty_cpu_schedulers_online)}
Errors: #{errors}
Median: #{Float.round(percentile.(0.5), 1)} ms
95th percentile: #{Float.round(percentile.(0.95), 1)} ms
Peak memory estimate: #{:erlang.system_info(:dirty_cpu_schedulers_online)} x #{Integer.pow(2, m_cost)} KiB
""")

if errors > 0, do: System.halt(1)
