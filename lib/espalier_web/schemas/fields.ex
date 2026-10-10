defmodule EspalierWeb.Schemas.Fields do
  @moduledoc """
  Member schemas shared by the request and response schemas of
  `EspalierWeb.Schemas`. Request members restrict type, length and values
  (ASVS 1.3.3): keys follow the key format of content packs
  (`^[a-z0-9][a-z0-9-]*$`, at most 255 characters).
  """

  alias OpenApiSpex.Schema

  @phases ~w(orient understand apply anchor update)
  @provenances ~w(invented sourced vendor_statement assumption placeholder)

  @doc "The maximum length of a key (a `varchar(255)` column)."
  def key_length, do: 255

  @doc "A key of a content pack in a request."
  def key_param(description) do
    %Schema{
      type: :string,
      minLength: 1,
      maxLength: key_length(),
      # `(?!\\n)` keeps PCRE's `$` from matching before a final line break.
      pattern: "^[a-z0-9][a-z0-9-]*$(?!\\n)",
      description: description
    }
  end

  @doc "A string member of a request with at most `max_length` characters."
  def request_string(max_length, description) do
    %Schema{type: :string, maxLength: max_length, description: description}
  end

  @doc """
  A public entry of an external identity provider (task 0004 step 35,
  `Espalier.Identity.Config.public_entry/1`).
  """
  def provider do
    object(%{
      key: string("The provider key of the configuration."),
      type: enum(~w(entra google oidc ldap)),
      kind: enum(~w(redirect credentials), "A redirect to the provider or a credentials form."),
      label: string(),
      start_url: string("The path where the sign-in starts.")
    })
  end

  @doc "A UUID."
  def uuid(description \\ nil),
    do: %Schema{type: :string, format: :uuid, description: description}

  @doc "A string."
  def string(description \\ nil), do: %Schema{type: :string, description: description}

  @doc "A string or `null`."
  def nullable_string(description \\ nil),
    do: %Schema{type: :string, nullable: true, description: description}

  @doc "A boolean."
  def boolean(description \\ nil), do: %Schema{type: :boolean, description: description}

  @doc "An integer."
  def integer(description \\ nil), do: %Schema{type: :integer, description: description}

  @doc "A timestamp in ISO 8601 (UTC)."
  def datetime(description \\ nil),
    do: %Schema{type: :string, format: :"date-time", description: description}

  @doc "A date in ISO 8601."
  def date(description \\ nil),
    do: %Schema{type: :string, format: :date, description: description}

  @doc "A string from a fixed set of values."
  def enum(values, description \\ nil),
    do: %Schema{type: :string, enum: values, description: description}

  @doc "A list of `items`."
  def array(items, description \\ nil),
    do: %Schema{type: :array, items: items, description: description}

  @doc "A list of UUIDs."
  def uuids(description \\ nil), do: array(uuid(), description)

  @doc "A list of strings."
  def strings(description \\ nil), do: array(string(), description)

  @doc "The phases of the five-phase arc (`Phase` in `domain-values.puml`)."
  def phases(description \\ nil), do: array(enum(@phases), description)

  @doc "A phase of the five-phase arc."
  def phase(description \\ nil), do: enum(@phases, description)

  @doc "The provenance of a block or an item (README principle 4)."
  def provenance(description \\ nil), do: enum(@provenances, description)

  @doc """
  An object with exactly the given properties, all required unless named in
  `optional`, and no other member.
  """
  def object(properties, opts \\ []) do
    optional = Keyword.get(opts, :optional, [])

    %Schema{
      type: :object,
      properties: properties,
      required: properties |> Map.keys() |> Enum.reject(&(&1 in optional)) |> Enum.sort(),
      additionalProperties: false,
      description: Keyword.get(opts, :description)
    }
  end
end
