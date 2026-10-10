defmodule Espalier.Catalog do
  @moduledoc """
  The Catalog context: programs and their content. Content arrives only
  through content packs: `Espalier.Catalog.Pack.Importer` validates a pack
  and stores it as a draft, and `Espalier.Catalog.Pack.Publisher` applies the
  draft to the catalog tables (README section 11). This module reads them.
  """

  import Ecto.Query, warn: false
  alias Espalier.Repo

  alias Espalier.Catalog.Program

  @doc """
  Returns the list of programs.
  """
  def list_programs do
    Repo.all(from p in Program, order_by: p.slug)
  end

  @doc """
  Gets a single program.

  Raises `Ecto.NoResultsError` if the Program does not exist.
  """
  def get_program!(id), do: Repo.get!(Program, id)

  @doc """
  Gets the program whose slug is the key of its content pack, or `nil`.
  """
  def get_program_by_slug(slug) when is_binary(slug), do: Repo.get_by(Program, slug: slug)
end
