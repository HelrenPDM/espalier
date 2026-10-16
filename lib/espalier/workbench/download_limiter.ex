defmodule Espalier.Workbench.DownloadLimiter do
  @moduledoc """
  Bounds the draft downloads that run at once (task 0018, step 16; ASVS
  15.2.2): at most `Espalier.Workbench.max_parallel_downloads/0` per node
  (2 by default) and one per user. The server is a server of
  `Espalier.Workbench.CheckLimiter` under the name of this module, so it
  answers `{:error, :checks_busy}` at once, without a queue, when it grants
  no slot, and a caller that dies frees its slot.

  `Espalier.Workbench.download/3` takes its slot here before it builds the
  zip, builds the zip in a slot of `CheckLimiter`, which it frees once the
  zip is written, and keeps the slot here while the zip is sent and its
  staging directory is removed. So at most `max_parallel_downloads/0` zips
  of downloads lie on disk per node, and a slow transfer holds no slot of
  the checks and imports.
  """

  alias Espalier.Workbench
  alias Espalier.Workbench.CheckLimiter

  @doc false
  def child_spec(opts), do: CheckLimiter.child_spec(Keyword.put_new(opts, :name, __MODULE__))

  @doc """
  Runs `fun` in a slot of the downloads for the user with the id `user_id`
  and frees the slot afterwards. Returns the result of `fun`, or
  `{:error, :checks_busy}` when every slot is taken or the user holds one.
  """
  @spec run(term(), (-> result)) :: result | {:error, :checks_busy} when result: term()
  def run(user_id, fun) when is_function(fun, 0),
    do: CheckLimiter.run(__MODULE__, Workbench.max_parallel_downloads(), user_id, fun)
end
