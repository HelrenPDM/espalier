defmodule Espalier.Identity.Ldap.Records do
  @moduledoc """
  The result records of `eldap.hrl` (task 0007, step 2). Code reads search
  results only through these macros: the runtime tuple of
  `eldap_search_result` has four elements, and its `controls` field is
  `:asn1_NOVALUE` or a list, depending on the server.
  """
  require Record

  Record.defrecord(
    :eldap_search_result,
    Record.extract(:eldap_search_result, from_lib: "eldap/include/eldap.hrl")
  )

  Record.defrecord(
    :eldap_entry,
    Record.extract(:eldap_entry, from_lib: "eldap/include/eldap.hrl")
  )
end
