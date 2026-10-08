defmodule Espalier.Accounts.PasswordPolicy do
  @moduledoc """
  Password rules for local accounts (README section 6.4, ASVS 6.2).

  `prepare/1` normalizes every password to Unicode NFC before the length
  check, the blocklist checks, the breached-password check, the Argon2id
  hash and the verification. This follows NIST SP 800-63B-4 section 3.1.1.2
  and is the documented deviation from ASVS 6.2.8 (decision D12,
  `docs/security/asvs-l2.md`). Directory passwords never pass through this
  module.

  Rules on the normalized value, each with its error code on `:password`:

    * 15 to 128 code points (`too_short`, `too_long`);
    * not in `priv/security/common-passwords.txt` (`common`);
    * its letters alone are no context word, and it contains neither the
      local part of the user's address nor the display name, each when 4 or
      more code points long (`context`);
    * with `PASSWORD_BREACH_CHECK=hibp`, not listed by the Pwned Passwords
      range API (`breached`).

  No composition rule exists, and no password expires.
  """

  import Ecto.Changeset

  alias Espalier.Accounts.BreachedPasswords

  @min_length 15
  @max_length 128
  @common_key {__MODULE__, :common}
  @context_key {__MODULE__, :context}

  @doc "Returns the password in Unicode NFC."
  @spec prepare(String.t()) :: String.t()
  def prepare(password) when is_binary(password), do: String.normalize(password, :nfc)

  @doc "The maximum length in code points, counted after `prepare/1`."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "True when the prepared password has more code points than allowed."
  @spec too_long?(String.t()) :: boolean()
  def too_long?(password) when is_binary(password) do
    password |> prepare() |> String.codepoints() |> length() > @max_length
  end

  @doc """
  Loads the common-password list and the context words (file and
  `:password_context_words`) into `:persistent_term`. Runs at boot.
  """
  @spec load_lists() :: :ok
  def load_lists do
    common =
      "common-passwords.txt"
      |> read_list()
      |> MapSet.new()

    context =
      "context-words.txt"
      |> read_list()
      |> Enum.concat(Application.get_env(:espalier, :password_context_words, []))
      |> Enum.map(&normalize_word/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    :persistent_term.put(@common_key, common)
    :persistent_term.put(@context_key, context)
    :ok
  end

  # read_list/1 receives only the two literal file names of load_lists/0, and
  # the directory comes from Application.app_dir/2; no input reaches the path.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_list(name) do
    :espalier
    |> Application.app_dir(Path.join("priv/security", name))
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim_trailing(&1, "\r"))
  end

  defp normalize_word(word),
    do: word |> String.trim() |> String.normalize(:nfc) |> String.downcase()

  @doc """
  Validates the prepared password in `changeset` for `user` and adds the
  error codes of the moduledoc.
  """
  @spec validate(Ecto.Changeset.t(), struct()) :: Ecto.Changeset.t()
  def validate(changeset, user) do
    changeset
    |> validate_length(:password, min: @min_length, count: :codepoints, message: "too_short")
    |> validate_length(:password, max: @max_length, count: :codepoints, message: "too_long")
    |> rename_length_errors()
    |> validate_lists(user)
  end

  defp rename_length_errors(changeset) do
    errors =
      Enum.map(changeset.errors, fn
        {:password, {"too_short", opts}} ->
          {:password, {"too_short", Keyword.put(opts, :validation, :too_short)}}

        {:password, {"too_long", opts}} ->
          {:password, {"too_long", Keyword.put(opts, :validation, :too_long)}}

        error ->
          error
      end)

    %{changeset | errors: errors}
  end

  defp validate_lists(%{valid?: false} = changeset, _user), do: changeset

  defp validate_lists(changeset, user) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> check(changeset, password, user)
    end
  end

  defp check(changeset, password, user) do
    cond do
      common?(password) -> add_code(changeset, :common)
      context?(password, user) -> add_code(changeset, :context)
      breached?(password) -> add_code(changeset, :breached)
      true -> changeset
    end
  end

  defp add_code(changeset, code),
    do: add_error(changeset, :password, to_string(code), validation: code)

  @doc "True when the lowercase prepared password is on the common-password list."
  @spec common?(String.t()) :: boolean()
  def common?(password) do
    MapSet.member?(:persistent_term.get(@common_key), String.downcase(prepare(password)))
  end

  @doc """
  True when the letters of the password alone equal a context word, or when
  the password contains the local part of the user's address or the display
  name (each when 4 or more code points long).
  """
  @spec context?(String.t(), struct() | nil) :: boolean()
  def context?(password, user) do
    lowered = password |> prepare() |> String.downcase()
    letters = String.replace(lowered, ~r/[^\p{L}]/u, "")

    letters in :persistent_term.get(@context_key) or
      Enum.any?(personal_words(user), &String.contains?(lowered, &1))
  end

  defp personal_words(nil), do: []

  defp personal_words(user) do
    local = if is_binary(user.email), do: user.email |> String.split("@") |> hd()

    [local, user.display_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_word/1)
    |> Enum.filter(&(length(String.codepoints(&1)) >= 4))
  end

  defp breached?(password) do
    Application.get_env(:espalier, :password_breach_check, :off) == :hibp and
      BreachedPasswords.check(password) == {:ok, :breached}
  end
end
