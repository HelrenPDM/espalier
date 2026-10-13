defmodule EspalierWeb.Schemas.Admin.PackDraftFields do
  @moduledoc """
  The members of the request schemas of the pack workbench (task 0016a,
  step 9) with the limits of `Espalier.Workbench`: a path of at most 527
  characters, a content of at most 1,048,576 characters (the context checks
  the bytes) and a `lock_version` of at least 1.
  """
  alias OpenApiSpex.Schema

  @doc "A path of the pack layout."
  def path do
    %Schema{
      type: :string,
      minLength: 1,
      maxLength: 527,
      description:
        "A path of the pack layout: a top-level YAML file, `modules/<dir>/<name>.yaml` " <>
          "or `modules/<dir>/lessons/<key>.md`, with at most 255 bytes per component."
    }
  end

  @doc "The text of a file."
  def content do
    %Schema{
      type: :string,
      maxLength: 1_048_576,
      description: "UTF-8 text without U+0000, at most 1,048,576 bytes."
    }
  end

  @doc "The `lock_version` of the draft that the change starts from."
  def lock_version do
    %Schema{
      type: :integer,
      minimum: 1,
      description: "The `lock_version` of the draft that the change starts from."
    }
  end
end
