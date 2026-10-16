defmodule Espalier.Media.Svg do
  @moduledoc """
  The SVG rebuild of the media processing (task 0018, step 6; ASVS 1.3.4
  and 1.5.1).

  `sanitize/1` writes every SVG file anew from an allowlist of elements and
  attributes, so the stored file holds no markup that the allowlist does not
  name. The player shows SVG files only through `<img>`, and the media route
  serves them with a `sandbox` CSP; the rebuild is the first of these layers.

  ## Before the parser

  A file above `Espalier.Media.svg_max_bytes/0` answers `too_large`, a file
  that is no valid UTF-8 or whose XML declaration names another encoding
  answers `encoding`, an entity declaration answers `entity`, a `DOCTYPE`
  answers `doctype`, and a processing instruction other than the XML
  declaration at the start answers `processing_instruction`. These checks
  read the bytes, so an entity or a DTD never reaches the parser. The
  checks for an entity declaration and a `DOCTYPE` compare the bytes after
  every `<!` with `ENTITY` and `DOCTYPE`, their letters in any case, so
  each of them reads the file once. A leading UTF-8 byte order mark is
  removed.

  An XML declaration at the start, `<?xml` followed by white space, must
  follow the production `XMLDecl` of XML 1.0 up to the first `?>`: white
  space, `version` with a value of the form `1.` and at least one digit,
  optionally white space and `encoding` with a name that starts with a
  letter and holds letters, digits, `.`, `_` and `-`, optionally white
  space and `standalone` with `yes` or `no`, optional white space and `?>`.
  Each value stands in single or double quotes, and white space may
  surround each `=`. Any other declaration answers `parse_error`, and so
  does a file that starts with `<?xml` and white space and holds no `?>`.
  The check of the encoding runs first, so a declaration that names
  another encoding answers `encoding`. xmerl reads the values of `version`
  and `standalone` as attribute values, where every predefined entity
  reference would cost a copy of the rest of the file, and it reads a
  quoted value up to its closing quote, also past the first `?>`. A value
  of the grammar holds neither a reference nor a `?>`, so the parser reads
  the same declaration as these checks. The check is one regular
  expression with possessive quantifiers, anchored at both ends, which
  reads the declaration once.

  One pass over the bytes then reads the markup as the parser does
  (comments, CDATA sections, the XML declaration, quoted attribute values,
  start and end tags) and answers `parse_error` for a start tag with more
  than 1,000 attributes, namespace declarations included, for an element
  nested deeper than 256 levels, root included, and for a start tag with
  more than 64 namespace declarations in scope, its own included. xmerl
  compares every attribute of a tag with the ones before it and looks up
  the prefix of every element name, the empty one included, and of every
  prefixed attribute name in the list of the namespace declarations in
  scope, and the rebuild recurses once per level, so the bounds limit the
  work per byte of the file.

  The same pass writes the predefined entity references `&lt;`, `&gt;`,
  `&amp;`, `&apos;` and `&quot;` inside the quoted attribute values of
  start tags as the character references `&#60;`, `&#62;`, `&#38;`,
  `&#39;` and `&#34;`, which stand for the same characters (XML 1.0,
  section 4.6), and the parser reads the rewritten file. xmerl puts the
  replacement text of a predefined reference in an attribute value in
  front of the rest of the document, so each such reference would cost a
  copy of the rest of the file, while it reads a character reference in
  place. Text, comments, CDATA sections and the XML declaration keep their
  bytes. A value without its closing quote runs to the end of the file and
  is rewritten up to there, and the parser then rejects the file.

  Of the files measured within these bounds, the slowest holds 1,048,576
  bytes of short start tags with six kept attributes each and takes about
  2.8 seconds on a development machine.

  ## Parser

  The rest is parsed with `:xmerl_sax_parser.stream/2` and the options
  `disallow_entities` and `skip_external_dtd`, so the parser resolves no
  entity and reads no external DTD (ASVS 1.5.1). A document that is not
  well-formed answers `parse_error`, and so does content after the root
  element other than comments and white space. The root element must be
  `svg` in the SVG namespace (`root`).

  ## Allowlists

  The element allowlist is `tags.svg` plus `tags.svgFilters` of DOMPurify
  3.4.17 plus `use`, and the attribute allowlist is `attrs.svg` plus
  `attrs.xml` of the same release, each name written in its case-sensitive
  SVG 1.1 spelling (`clipPath`, `linearGradient`, `viewBox`,
  `preserveAspectRatio`, `stdDeviation`) and compared exactly. DOMPurify
  lists the names in lower case. `tags.svg` of that release also holds
  `enterkeyhint`, `exportparts`, `inputmode` and `part`, which are HTML
  attribute names and no SVG elements, so the list below leaves them out.

  The allowlist omits `script`, `foreignObject`, `iframe`, the animation
  elements `animate`, `animateColor`, `animateMotion`, `animateTransform`
  and `set`, `mpath` and `metadata`. An element outside the allowlist or
  outside the SVG namespace is dropped with its content, and so is an
  element inside a `style` element, which keeps only its text. `a` is unwrapped:
  the element and its attributes go, its children stay in its place; the
  rebuild moves them as one nested list and flattens it once at the next
  kept ancestor, so nested `a` elements cost no copy per level. An
  `image` element anywhere in the document rejects the file
  (`embedded_image`), because a raster embedded in an SVG would keep its
  metadata and pass an unconverted decoder input to the browsers.

  An attribute stays when it is unprefixed and on the allowlist, or when it
  is `href` or `title` in the XLink namespace or `id` or `space` in the XML
  namespace (`xlink:href`, `xlink:title`, `xml:id`, `xml:space`). Every
  attribute whose name starts with `on` is dropped. `href` and `xlink:href`
  stay only with a value of the form `#<id>`, an internal reference such as
  the one of `use`, of a gradient or of `textPath`; every other value drops
  the attribute.

  ## CSS

  Every value of a kept attribute, the `style` attribute among them, and
  the text of every kept `style` element are checked as CSS. A backslash
  anywhere in the text rejects the file (`css`), so no CSS escape hides a
  name. A scanner then reads the text once as the CSS tokenizer does:

    * A string in double or single quotes is opaque: a `/*` inside it
      starts no comment. Its content becomes empty, unless it is an
      internal reference `#<id>`, which `url("#<id>")` needs, so a word
      inside a string, such as `content: "transition: none"`, counts as no
      property. A string that reaches a line break or the end of the text
      rejects the file (`css`), also in a value that no browser reads as
      CSS, such as `xlink:title="Don't"`.
    * A comment outside a string becomes a space. A comment without its
      `*/` rejects the file (`css`).
    * An unquoted `url(` runs to the next `)`, which the tokenizer reads as
      one token whatever it holds, so a quote or a `/*` inside it starts
      neither a string nor a comment. An unquoted `url(` without `)`
      rejects the file (`css`).

  On the scanned text, a `url(` other than `url(#<id>)`, also with quotes
  around the reference, `@import`, `expression(`, `image-set(`,
  `-webkit-image-set(`, `image(`, `cross-fade(`, `element(` and `src(`
  reject the file (`css`), so no style loads a resource. An `@keyframes`
  rule and the properties `animation`, `animation-*`, `transition` and
  `transition-*`, also with a vendor prefix and in any case, followed by
  `:`, reject the file (`animation`) wherever no identifier character
  (letter, digit, `_`, `-` or a non-ASCII character) precedes the name, so
  also after the `}` of a nested rule and in a selector such as
  `.transition:hover`, and an SVG never moves. The checks run through `:re`
  with `report_errors`, and a match limit of the engine counts as a match,
  so no check passes because the engine gave up.

  ## Output

  The output names every element without a prefix and declares the SVG
  namespace on the root, and the XLink namespace there when an `xlink:`
  attribute stays. Attributes keep their order; a second attribute with the
  same output name, which two prefixes of one namespace can produce, is
  dropped. Comments and CDATA markers are not written. Text and attribute
  values are escaped as `Espalier.Interop.xml_escape/1` does, and a carriage
  return, and in attribute values also a tab and a line feed, are written
  as character references, because a parser normalizes them. The output is
  deterministic, and a second `sanitize/1` of it gives the same bytes.

  ## Facts

  `width` and `height` come from the attributes of the root when they are
  numbers without a unit or with `px`, rounded, and at least 1. When only
  one of them is such a number, the other follows from the aspect ratio of
  `viewBox`; when neither is, both come from `viewBox`. Numbers outside
  1.0e-9 to 1.0e15 count as absent, which keeps the arithmetic within the
  float range, and a value that cannot be determined or that exceeds
  2,147,483,647, the largest value of the integer columns, is `nil`.
  """

  alias Espalier.{Interop, Media}

  @typedoc "The reason tags of a rejected SVG file."
  @type tag ::
          :too_large
          | :encoding
          | :doctype
          | :entity
          | :processing_instruction
          | :parse_error
          | :root
          | :embedded_image
          | :css
          | :animation

  @typedoc "The size of the SVG in CSS pixels, when the root names it."
  @type facts :: %{width: pos_integer() | nil, height: pos_integer() | nil}

  @svg_ns ~c"http://www.w3.org/2000/svg"
  @xlink_ns ~c"http://www.w3.org/1999/xlink"
  @xml_ns ~c"http://www.w3.org/XML/1998/namespace"

  @bom "\uFEFF"

  # tags.svg of DOMPurify 3.4.17 in SVG 1.1 spelling, without the omitted
  # elements (animateColor, animateMotion, animateTransform, metadata,
  # mpath), without a (unwrapped) and image (rejected), and without the
  # HTML attribute names enterkeyhint, exportparts, inputmode and part.
  @svg_tags ~w(svg altGlyph altGlyphDef altGlyphItem circle clipPath defs desc ellipse
               filter font g glyph glyphRef hkern line linearGradient marker mask path
               pattern polygon polyline radialGradient rect stop style switch symbol text
               textPath title tref tspan view vkern)

  # tags.svgFilters of DOMPurify 3.4.17.
  @svg_filter_tags ~w(feBlend feColorMatrix feComponentTransfer feComposite
                      feConvolveMatrix feDiffuseLighting feDisplacementMap feDistantLight
                      feDropShadow feFlood feFuncA feFuncB feFuncG feFuncR feGaussianBlur
                      feImage feMerge feMergeNode feMorphology feOffset fePointLight
                      feSpecularLighting feSpotLight feTile feTurbulence)

  @elements MapSet.new(@svg_tags ++ @svg_filter_tags ++ ["use"])

  # attrs.svg of DOMPurify 3.4.17 in SVG 1.1 spelling. xmlns of that list is
  # a namespace declaration, which the output writes itself.
  @attributes MapSet.new(~w(
    accent-height accumulate additive alignment-baseline amplitude ascent
    attributeName attributeType azimuth baseFrequency baseline-shift begin bias by
    class clip clipPathUnits clip-path clip-rule color color-interpolation
    color-interpolation-filters color-profile color-rendering cx cy d dx dy
    diffuseConstant direction display divisor dominant-baseline dur edgeMode
    elevation end exponent fill fill-opacity fill-rule filter filterUnits
    flood-color flood-opacity font-family font-size font-size-adjust font-stretch
    font-style font-variant font-weight fx fy g1 g2 glyph-name glyphRef
    gradientUnits gradientTransform height href id image-rendering in in2
    intercept k k1 k2 k3 k4 kerning keyPoints keySplines keyTimes lang
    lengthAdjust letter-spacing kernelMatrix kernelUnitLength lighting-color local
    marker-end marker-mid marker-start markerHeight markerUnits markerWidth
    maskContentUnits maskUnits max mask mask-type media method mode min name
    numOctaves offset operator opacity order orient orientation origin overflow
    paint-order path pathLength patternContentUnits patternTransform patternUnits
    pointer-events points preserveAlpha preserveAspectRatio primitiveUnits r rx ry
    radius refX refY repeatCount repeatDur restart result rotate scale seed
    shape-rendering slope specularConstant specularExponent spreadMethod
    startOffset stdDeviation stitchTiles stop-color stop-opacity stroke-dasharray
    stroke-dashoffset stroke-linecap stroke-linejoin stroke-miterlimit
    stroke-opacity stroke stroke-width style surfaceScale systemLanguage tabindex
    tableValues targetX targetY transform transform-origin text-anchor
    text-decoration text-orientation text-rendering textLength type u1 u2 unicode
    values vector-effect viewBox visibility version vert-adv-y vert-origin-x
    vert-origin-y width word-spacing wrap writing-mode xChannelSelector
    yChannelSelector x x1 x2 y y1 y2 z zoomAndPan
  ))

  # attrs.xml of DOMPurify 3.4.17 by namespace and local name; xmlns:xlink
  # is the declaration that the output writes on the root.
  @xlink_attributes ~w(href title)
  @xml_attributes ~w(id space)

  @internal_ref ~r/\A#[A-Za-z_][A-Za-z0-9_.-]*\z/

  # On the scanned CSS: a url( that is not url(#<id>), and url with white
  # space before "(". The quantifiers are possessive, so no check
  # backtracks.
  @external_url ~r/url(?:\s++\(|\((?!\s*+(["']?+)#[A-Za-z_][A-Za-z0-9_.-]*+\1\s*+\)))/i
  @resource ~r/@import|(?:expression|image-set|image|cross-fade|element|src)\s*+\(/i
  # A property name counts where no identifier character (letter, digit,
  # "_", "-" or a byte of a non-ASCII character) precedes it.
  @animation ~r/@(?:-[a-z]++-)?keyframes|(?<![a-z0-9_\x80-\xff-])(?:-[a-z]++-)?(?:animation|transition)(?:-[a-z0-9-]*+)?\s*+:/i

  @css_space ~c" \t\n\r\f"
  @xml_space ~c" \t\r\n"

  # The production XMLDecl of XML 1.0 (fifth edition) with the productions
  # VersionInfo, EncodingDecl, SDDecl, Eq and S, anchored at both ends. The
  # quantifiers are possessive, so the check reads the declaration once.
  @s "[ \\t\\r\\n]"
  @eq "#{@s}*+=#{@s}*+"
  @enc_name "[A-Za-z][A-Za-z0-9._-]*+"
  @xml_declaration Regex.compile!(
                     "\\A<\\?xml#{@s}++version#{@eq}(?:\"1\\.[0-9]++\"|'1\\.[0-9]++')" <>
                       "(?:#{@s}++encoding#{@eq}(?:\"#{@enc_name}\"|'#{@enc_name}'))?+" <>
                       "(?:#{@s}++standalone#{@eq}(?:\"(?:yes|no)\"|'(?:yes|no)'))?+" <>
                       "#{@s}*+\\?>\\z"
                   )

  @max_attributes 1_000
  @max_depth 256
  @max_namespaces 64

  # The predefined entity references and the character references of the
  # same characters (XML 1.0, section 4.6).
  @char_references %{
    "&lt;" => "&#60;",
    "&gt;" => "&#62;",
    "&amp;" => "&#38;",
    "&apos;" => "&#39;",
    "&quot;" => "&#34;"
  }
  @predefined Map.keys(@char_references)

  # The white space, the separators and px are possessive. With greedy
  # quantifiers, a number followed by a long run of white space and another
  # character makes the engine try every split of the run between the two
  # white space quantifiers around px, which takes quadratic time.
  @number "[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
  @length Regex.compile!("\\A\\s*+(#{@number})\\s*+(?:px)?+\\s*+\\z")
  @view_box Regex.compile!(
              "\\A\\s*+(#{@number})[\\s,]++(#{@number})[\\s,]++(#{@number})[\\s,]++(#{@number})\\s*+\\z"
            )
  @max_dimension 2_147_483_647

  @doc """
  Rebuilds `binary` as an SVG document from the allowlists and returns it
  with its facts, or the reason tag of the rejection.
  """
  @spec sanitize(binary()) :: {:ok, binary(), facts()} | {:error, {:invalid_svg, tag()}}
  def sanitize(binary) when is_binary(binary) do
    body = strip_bom(binary)

    with :ok <- check_size(binary),
         :ok <- check_encoding(body),
         :ok <- check_xml_declaration(body),
         :ok <- check_declarations(body),
         {:ok, document} <- check_markup(body),
         {:ok, root} <- parse(document) do
      {:ok, IO.iodata_to_binary(render_root(root)), facts(root)}
    else
      {:error, tag} -> {:error, {:invalid_svg, tag}}
    end
  end

  ## Checks before the parser

  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(binary), do: binary

  defp check_size(binary) do
    if byte_size(binary) > Media.svg_max_bytes(), do: {:error, :too_large}, else: :ok
  end

  defp check_encoding(body) do
    cond do
      not String.valid?(body) -> {:error, :encoding}
      declared_encoding_ok?(body) -> :ok
      true -> {:error, :encoding}
    end
  end

  # The encoding pseudo-attribute of the XML declaration, when present, must
  # name UTF-8, because xmerl decodes the bytes by it.
  defp declared_encoding_ok?(body) do
    case split_declaration(body) do
      {declaration, _rest} ->
        case Regex.run(~r/\sencoding\s*=\s*(["'])([^"']*)\1/, declaration) do
          [_match, _quote, encoding] -> String.downcase(encoding) == "utf-8"
          nil -> true
        end

      nil ->
        true
    end
  end

  # A body that starts with "<?xml" and white space starts with the XML
  # declaration, which xmerl reads with the values of version and standalone
  # as attribute values, also past the first "?>". The declaration up to the
  # first "?>" must follow XMLDecl, whose values hold neither a reference
  # nor a "?>", so xmerl reads the same declaration. A start without "?>"
  # has no such declaration and answers parse_error as well.
  defp check_xml_declaration(<<"<?xml", c, _rest::binary>> = body) when c in @xml_space do
    with {declaration, _rest} <- split_declaration(body),
         true <- Regex.match?(@xml_declaration, declaration) do
      :ok
    else
      _unterminated_or_no_match -> {:error, :parse_error}
    end
  end

  defp check_xml_declaration(_body), do: :ok

  defp check_declarations(body) do
    cond do
      declaration?(body, "ENTITY") -> {:error, :entity}
      declaration?(body, "DOCTYPE") -> {:error, :doctype}
      String.contains?(after_declaration(body), "<?") -> {:error, :processing_instruction}
      true -> :ok
    end
  end

  # Whether a "<!" of the body is followed by name, its ASCII letters in
  # any case. Every "<!" is read once. A case-insensitive regular expression
  # would search the rest of the body for the last letter of the name at
  # every "<" when that letter occurs in one case only, which takes
  # quadratic time.
  defp declaration?(body, name) do
    case :binary.split(body, "<!") do
      [_before, rest] ->
        prefix = binary_part(rest, 0, min(byte_size(name), byte_size(rest)))
        String.upcase(prefix, :ascii) == name or declaration?(rest, name)

      [_none] ->
        false
    end
  end

  defp after_declaration(body) do
    case split_declaration(body) do
      {_declaration, rest} -> rest
      nil -> body
    end
  end

  # The XML declaration at the start: "<?xml" followed by white space, up to
  # the first "?>".
  defp split_declaration(<<"<?xml", c, _rest::binary>> = body) when c in ~c" \t\r\n" do
    case :binary.match(body, "?>") do
      {position, 2} ->
        length = position + 2
        {binary_part(body, 0, length), binary_part(body, length, byte_size(body) - length)}

      :nomatch ->
        nil
    end
  end

  defp split_declaration(_body), do: nil

  ## Bounds of the markup

  # Reads the markup as xmerl does, up to the first point where xmerl would
  # stop with an error; what follows such a point is never parsed. depth
  # counts the open elements, scope the namespace declarations of the open
  # elements, and stack holds the declarations of each open element. values
  # collects the attribute values that hold a predefined entity reference,
  # the last one first, and the body comes back with these references
  # written as character references.
  defp check_markup(body) do
    with {:ok, values} <- markup(body, 0, 0, [], []),
         do: {:ok, char_references(body, values)}
  end

  defp markup(rest, depth, scope, stack, values) do
    case :binary.split(rest, "<") do
      [_text, rest] -> markup_open(rest, depth, scope, stack, values)
      [_text] -> {:ok, values}
    end
  end

  defp markup_open("!--" <> rest, depth, scope, stack, values),
    do: markup_skip(rest, "-->", depth, scope, stack, values)

  defp markup_open("![CDATA[" <> rest, depth, scope, stack, values),
    do: markup_skip(rest, "]]>", depth, scope, stack, values)

  defp markup_open("?" <> rest, depth, scope, stack, values),
    do: markup_skip(rest, "?>", depth, scope, stack, values)

  defp markup_open("/" <> rest, depth, scope, [own | stack], values),
    do: markup_skip(rest, ">", depth - 1, scope - own, stack, values)

  defp markup_open("/" <> rest, depth, scope, [], values),
    do: markup_skip(rest, ">", depth, scope, [], values)

  defp markup_open(_rest, depth, _scope, _stack, _values) when depth >= @max_depth,
    do: {:error, :parse_error}

  defp markup_open(rest, depth, scope, stack, values) do
    {_name, rest} = take_name(rest)
    start_tag(rest, {depth, scope, stack}, 0, 0, values)
  end

  defp markup_skip(rest, stop, depth, scope, stack, values) do
    case :binary.split(rest, stop) do
      [_skipped, rest] -> markup(rest, depth, scope, stack, values)
      [_unterminated] -> {:ok, values}
    end
  end

  # The attributes of a start tag; attributes counts them and own the
  # namespace declarations among them.
  defp start_tag(<<c, rest::binary>>, open, attributes, own, values) when c in @xml_space,
    do: start_tag(rest, open, attributes, own, values)

  defp start_tag("/>" <> rest, {depth, scope, stack}, _attributes, _own, values),
    do: markup(rest, depth, scope, stack, values)

  defp start_tag(">" <> rest, {depth, scope, stack}, _attributes, own, values),
    do: markup(rest, depth + 1, scope + own, [own | stack], values)

  # A value without its closing quote runs to the end of the body; xmerl
  # rejects it there, after it has read its references.
  defp start_tag(<<quote, rest::binary>>, open, attributes, own, values)
       when quote in [?", ?'] do
    case :binary.split(rest, <<quote>>) do
      [value, after_value] ->
        start_tag(after_value, open, attributes, own, add_value(values, value, rest))

      [_unterminated] ->
        {:ok, add_value(values, rest, rest)}
    end
  end

  defp start_tag(<<c, rest::binary>>, open, attributes, own, values) when c in [?=, ?/],
    do: start_tag(rest, open, attributes, own, values)

  defp start_tag("", _open, _attributes, _own, values), do: {:ok, values}

  defp start_tag(rest, {_depth, scope, _stack} = open, attributes, own, values) do
    {name, rest} = take_name(rest)
    attributes = attributes + 1
    own = if name == "xmlns" or String.starts_with?(name, "xmlns:"), do: own + 1, else: own

    if attributes > @max_attributes or scope + own > @max_namespaces,
      do: {:error, :parse_error},
      else: start_tag(rest, open, attributes, own, values)
  end

  # rest starts with the value and runs to the end of the body, so its size
  # locates the value in the body.
  defp add_value(values, value, rest) do
    if String.contains?(value, @predefined),
      do: [{byte_size(rest), value} | values],
      else: values
  end

  # The body with the predefined entity references of the collected values
  # written as character references; every other byte stays. values holds
  # the last value first, so the parts are built from the end of the body.
  defp char_references(body, []), do: body

  defp char_references(body, values) do
    size = byte_size(body)

    {parts, first_start} =
      Enum.reduce(values, {[], size}, fn {remaining, value}, {parts, next_start} ->
        start = size - remaining
        stop = start + byte_size(value)
        between = binary_part(body, stop, next_start - stop)
        {[char_reference(value), between | parts], start}
      end)

    IO.iodata_to_binary([binary_part(body, 0, first_start) | parts])
  end

  defp char_reference(value),
    do: String.replace(value, @predefined, &Map.fetch!(@char_references, &1))

  # A name runs to white space, "=", ">", "/" or a quote.
  defp take_name(rest) do
    case :binary.match(rest, [" ", "\t", "\r", "\n", "=", ">", "/", "\"", "'"]) do
      {position, 1} ->
        {binary_part(rest, 0, position), binary_part(rest, position, byte_size(rest) - position)}

      :nomatch ->
        {rest, ""}
    end
  end

  ## Parser

  defp parse(body) do
    options = [
      :disallow_entities,
      :skip_external_dtd,
      event_fun: &event/3,
      event_state: %{stack: [], root: nil}
    ]

    case :xmerl_sax_parser.stream(body, options) do
      {:ok, %{root: {_name, _attrs, _children} = root}, rest} ->
        if trailing_misc?(rest), do: {:ok, root}, else: {:error, :parse_error}

      {:invalid_svg, _location, tag, _end_tags, _state} ->
        {:error, tag}

      _other ->
        {:error, :parse_error}
    end
  catch
    # xmerl reports malformed input through its return value; an exception
    # or an exit inside the parser counts as a parse error as well.
    kind, _reason when kind in [:error, :exit] -> {:error, :parse_error}
  end

  # xmerl returns the input after the end tag of the root unparsed, and
  # parses it only after a self-closing root, so the rest may hold the
  # comments and the white space that XML admits after the root element.
  defp trailing_misc?(rest) do
    case String.trim_leading(rest) do
      "" ->
        true

      "<!--" <> comment ->
        case :binary.split(comment, "-->") do
          [_comment, after_comment] -> trailing_misc?(after_comment)
          [_unterminated] -> false
        end

      _other ->
        false
    end
  end

  # Each frame of the stack is {:element, name, attrs, children} or
  # {:unwrap, children} for an a element, with the children in reverse
  # order, or :drop for an element that is dropped with its content. An
  # unwrapped element passes its children to its parent as one nested list
  # in reverse order, and a kept element flattens its children once at its
  # end, so a chain of a elements copies no list per level.
  defp event({:startElement, uri, local, _qname, attrs}, _location, state) do
    %{state | stack: [start_frame(state.stack, uri, local, attrs) | state.stack]}
  end

  defp event({:endElement, _uri, _local, _qname}, _location, state) do
    [frame | stack] = state.stack
    end_frame(frame, %{state | stack: stack})
  end

  defp event({kind, chars}, _location, %{stack: [frame | stack]} = state)
       when kind in [:characters, :ignorableWhitespace] do
    %{state | stack: [add_text(frame, chars) | stack]}
  end

  defp event(_event, _location, state), do: state

  defp start_frame([], uri, local, attrs) do
    if uri == @svg_ns and local == ~c"svg" do
      {:element, "svg", attributes(attrs), []}
    else
      reject(:root)
    end
  end

  # A style element keeps only its own text, which the CSS check reads, so
  # an element inside it is dropped like one inside a dropped element.
  defp start_frame([{:element, "style", _attrs, _children} | _stack], uri, local, attrs),
    do: start_frame([:drop], uri, local, attrs)

  defp start_frame([:drop | _stack], uri, local, _attrs) do
    if uri == @svg_ns and local == ~c"image", do: reject(:embedded_image), else: :drop
  end

  defp start_frame(_stack, @svg_ns, ~c"image", _attrs), do: reject(:embedded_image)
  defp start_frame(_stack, @svg_ns, ~c"a", _attrs), do: {:unwrap, []}

  defp start_frame(_stack, @svg_ns, local, attrs) do
    name = List.to_string(local)

    if MapSet.member?(@elements, name),
      do: {:element, name, attributes(attrs), []},
      else: :drop
  end

  defp start_frame(_stack, _uri, _local, _attrs), do: :drop

  defp end_frame(:drop, state), do: state

  defp end_frame({:unwrap, children}, %{stack: [parent | stack]} = state) do
    %{state | stack: [add_child(parent, children) | stack]}
  end

  defp end_frame({:element, name, attrs, children}, state) do
    children = children |> List.flatten() |> Enum.reverse()
    if name == "style", do: check_css(Enum.join(Enum.filter(children, &is_binary/1)))
    node = {name, attrs, children}

    case state.stack do
      [] -> %{state | root: node}
      [parent | stack] -> %{state | stack: [add_child(parent, node) | stack]}
    end
  end

  # A child is a node, a text or the nested list of an unwrapped element.
  defp add_child(:drop, _child), do: :drop
  defp add_child({:unwrap, children}, child), do: {:unwrap, [child | children]}

  defp add_child({:element, name, attrs, children}, child),
    do: {:element, name, attrs, [child | children]}

  defp add_text(:drop, _chars), do: :drop
  defp add_text(frame, []), do: frame
  defp add_text(frame, chars), do: add_child(frame, List.to_string(chars))

  defp reject(tag), do: throw({:invalid_svg, tag})

  ## Attributes

  defp attributes(attrs) do
    attrs
    |> Enum.flat_map(&attribute/1)
    |> Enum.uniq_by(fn {name, _value} -> name end)
    |> Enum.map(fn {_name, value} = attribute ->
      check_css(value)
      attribute
    end)
  end

  defp attribute({[], [], local, value}) do
    name = List.to_string(local)
    value = List.to_string(value)

    cond do
      String.starts_with?(String.downcase(name), "on") -> []
      not MapSet.member?(@attributes, name) -> []
      name == "href" -> internal_ref("href", value)
      true -> [{name, value}]
    end
  end

  defp attribute({@xlink_ns, _prefix, local, value}) do
    name = List.to_string(local)
    value = List.to_string(value)

    cond do
      name not in @xlink_attributes -> []
      name == "href" -> internal_ref("xlink:href", value)
      true -> [{"xlink:" <> name, value}]
    end
  end

  defp attribute({@xml_ns, _prefix, local, value}) do
    name = List.to_string(local)
    if name in @xml_attributes, do: [{"xml:" <> name, List.to_string(value)}], else: []
  end

  defp attribute(_attribute), do: []

  defp internal_ref(name, value) do
    if Regex.match?(@internal_ref, value), do: [{name, value}], else: []
  end

  ## CSS

  defp check_css(text) do
    if String.contains?(text, "\\"), do: reject(:css)
    css = scan_css(text, "")

    cond do
      matches?(@external_url, css) -> reject(:css)
      matches?(@resource, css) -> reject(:css)
      matches?(@animation, css) -> reject(:animation)
      true -> :ok
    end
  end

  # A match limit of the engine answers {:error, _}, which counts as a match.
  defp matches?(regex, css),
    do: :re.run(css, regex.re_pattern, [:report_errors, capture: :none]) != :nomatch

  # One pass over the CSS as the tokenizer reads it, without escapes, which
  # check_css/1 rejects first: a comment becomes a space, the content of a
  # string becomes empty unless it is an internal reference, and an
  # unquoted url( stays as it is up to its ")".
  defp scan_css("/*" <> rest, css) do
    case :binary.split(rest, "*/") do
      [_comment, rest] -> scan_css(rest, <<css::binary, " ">>)
      [_unterminated] -> reject(:css)
    end
  end

  defp scan_css(<<quote, rest::binary>>, css) when quote in [?", ?'] do
    case :binary.match(rest, [<<quote>>, "\n", "\r", "\f"]) do
      {position, 1} when binary_part(rest, position, 1) == <<quote>> ->
        content = binary_part(rest, 0, position)
        rest = binary_part(rest, position + 1, byte_size(rest) - position - 1)
        kept = if Regex.match?(@internal_ref, content), do: content, else: ""
        scan_css(rest, <<css::binary, quote, kept::binary, quote>>)

      _line_break_or_end ->
        reject(:css)
    end
  end

  defp scan_css(<<u, r, l, ?(, rest::binary>>, css)
       when u in ~c"uU" and r in ~c"rR" and l in ~c"lL" do
    css = <<css::binary, u, r, l, ?(>>

    case skip_css_space(rest) do
      <<quote, _rest::binary>> when quote in [?", ?'] ->
        scan_css(rest, css)

      _unquoted ->
        case :binary.split(rest, ")") do
          [url, rest] -> scan_css(rest, <<css::binary, url::binary, ?)>>)
          [_unterminated] -> reject(:css)
        end
    end
  end

  defp scan_css(<<c, rest::binary>>, css), do: scan_css(rest, <<css::binary, c>>)
  defp scan_css("", css), do: css

  defp skip_css_space(<<c, rest::binary>>) when c in @css_space, do: skip_css_space(rest)
  defp skip_css_space(rest), do: rest

  ## Output

  defp render_root({"svg", attrs, children}) do
    xlink =
      if xlink?({"svg", attrs, children}),
        do: [~s( xmlns:xlink="http://www.w3.org/1999/xlink")],
        else: []

    ["<svg", ~s( xmlns="http://www.w3.org/2000/svg"), xlink, render_rest(attrs, children, "svg")]
  end

  defp render_node({name, attrs, children}), do: ["<", name, render_rest(attrs, children, name)]
  defp render_node(text) when is_binary(text), do: escape_text(text)

  defp render_rest(attrs, [], _name), do: [render_attributes(attrs), "/>"]

  defp render_rest(attrs, children, name) do
    [render_attributes(attrs), ">", Enum.map(children, &render_node/1), "</", name, ">"]
  end

  defp render_attributes(attrs) do
    Enum.map(attrs, fn {name, value} -> [" ", name, "=\"", escape_attribute(value), "\""] end)
  end

  defp xlink?({_name, attrs, children}) do
    Enum.any?(attrs, fn {name, _value} -> String.starts_with?(name, "xlink:") end) or
      Enum.any?(children, &(is_tuple(&1) and xlink?(&1)))
  end

  defp escape_text(text), do: text |> Interop.xml_escape() |> String.replace("\r", "&#13;")

  defp escape_attribute(value) do
    value
    |> Interop.xml_escape()
    |> String.replace(["\t", "\n", "\r"], fn
      "\t" -> "&#9;"
      "\n" -> "&#10;"
      "\r" -> "&#13;"
    end)
  end

  ## Facts

  defp facts({"svg", attrs, _children}) do
    attrs = Map.new(attrs)
    width = length_value(attrs["width"])
    height = length_value(attrs["height"])

    {width, height} =
      case {width, height, view_box(attrs["viewBox"])} do
        {nil, nil, {box_width, box_height}} ->
          {box_width, box_height}

        {nil, height, {box_width, box_height}} when height != nil ->
          {height * box_width / box_height, height}

        {width, nil, {box_width, box_height}} when width != nil ->
          {width, width * box_height / box_width}

        {width, height, _box} ->
          {width, height}
      end

    %{width: dimension(width), height: dimension(height)}
  end

  defp length_value(nil), do: nil

  defp length_value(value) do
    case Regex.run(@length, value, capture: :all_but_first) do
      [number] -> positive(number)
      nil -> nil
    end
  end

  defp view_box(nil), do: nil

  defp view_box(value) do
    with [_x, _y, width, height] <- Regex.run(@view_box, value, capture: :all_but_first),
         width when width != nil <- positive(width),
         height when height != nil <- positive(height) do
      {width, height}
    else
      _other -> nil
    end
  end

  # A number of the SVG grammar as a float from 1.0e-9 to 1.0e15, or nil.
  # Float.parse/1 needs a digit on both sides of the point and answers
  # :error for an exponent beyond the float range. The bounds keep the
  # aspect ratio arithmetic within the float range.
  defp positive(number) do
    number =
      number
      |> String.replace(~r/\A([+-]?)\./, "\\g{1}0.")
      |> String.replace(~r/\.(?![0-9])/, ".0")

    case Float.parse(number) do
      {value, ""} when value >= 1.0e-9 and value <= 1.0e15 -> value
      _other -> nil
    end
  end

  defp dimension(nil), do: nil

  defp dimension(value) do
    rounded = max(round(value), 1)
    if rounded > @max_dimension, do: nil, else: rounded
  end
end
