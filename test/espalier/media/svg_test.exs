defmodule Espalier.Media.SvgTest do
  @moduledoc """
  The SVG rebuild of task 0018, step 6 (ASVS 1.3.4 and 1.5.1): the attack
  vectors of the h5sc and cure53 SVG collections, CSS that hides a rule
  from a comment-based check, the bounds of the markup and the work per
  file, Inkscape and Illustrator samples, the facts, and the idempotence of
  the output.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Espalier.Interop
  alias Espalier.Media
  alias Espalier.Media.Svg

  @fixtures Path.expand("../../fixtures/media", __DIR__)

  @open ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">|
  @plain_open ~s|<svg xmlns="http://www.w3.org/2000/svg">|

  # A quadratic path of the parser or the rebuild takes about a minute on
  # the inputs of "work per file"; 10 seconds leave room for slow runners.
  @time_bound_us 10_000_000

  # A full file that the parser rejects at its first bytes takes
  # milliseconds, while a quadratic check before the parser takes several
  # seconds on it.
  @check_bound_us 1_000_000

  defp svg(content), do: @open <> content <> "</svg>"

  defp sanitize!(binary) do
    assert {:ok, output, facts} = Svg.sanitize(binary)
    assert Svg.sanitize(output) == {:ok, output, facts}
    output
  end

  defp rejects(binary), do: elem(Svg.sanitize(binary), 1)

  defp facts(root_attributes) do
    {:ok, _output, facts} =
      Svg.sanitize(~s|<svg xmlns="http://www.w3.org/2000/svg" #{root_attributes}/>|)

    facts
  end

  defp many_attributes(range), do: Enum.map_join(range, &~s| a#{&1}=""|)

  defp declarations(range), do: Enum.map_join(range, &~s| xmlns:p#{&1}="urn:p#{&1}"|)

  defp nested(name, levels, content) do
    String.duplicate("<#{name}>", levels) <> content <> String.duplicate("</#{name}>", levels)
  end

  # head, as many units as svg_max_bytes admits, and tail.
  defp fill(head, unit, tail) do
    count = div(Media.svg_max_bytes() - byte_size(head) - byte_size(tail), byte_size(unit))
    {head <> String.duplicate(unit, count) <> tail, count}
  end

  # The sanitize runs in a task that is killed at the bound, so a quadratic
  # path fails the test at the bound instead of after minutes.
  defp timed_sanitize(binary, bound_us \\ @time_bound_us) do
    assert byte_size(binary) <= Media.svg_max_bytes()
    task = Task.async(fn -> :timer.tc(fn -> Svg.sanitize(binary) end) end)

    case Task.yield(task, div(bound_us, 1_000)) || Task.shutdown(task, :brutal_kill) do
      {:ok, {micros, result}} ->
        assert micros < bound_us, "sanitize took #{micros} µs"
        result

      nil ->
        flunk("sanitize took more than #{bound_us} µs")
    end
  end

  describe "checks before the parser" do
    test "a file above svg_max_bytes answers too_large" do
      padding = String.duplicate(" ", Media.svg_max_bytes())
      assert rejects(svg(padding)) == {:invalid_svg, :too_large}
    end

    test "invalid UTF-8 and another declared encoding answer encoding" do
      assert rejects(svg(<<0xFF, 0xFE>>)) == {:invalid_svg, :encoding}

      latin1 = ~s|<?xml version="1.0" encoding="ISO-8859-1"?>| <> svg("ä")
      assert rejects(latin1) == {:invalid_svg, :encoding}

      utf8 = ~s|<?xml version="1.0" encoding="UTF-8"?>| <> svg("<text>ä</text>")
      assert sanitize!(utf8) =~ "<text>ä</text>"
    end

    test "entity expansion answers entity before the parser" do
      laughs = """
      <?xml version="1.0"?>
      <!DOCTYPE svg [
        <!ENTITY lol "lol">
        <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
        <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
      ]>
      <svg xmlns="http://www.w3.org/2000/svg"><text>&lol3;</text></svg>
      """

      assert rejects(laughs) == {:invalid_svg, :entity}

      external = """
      <!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
      <svg xmlns="http://www.w3.org/2000/svg"><text>&xxe;</text></svg>
      """

      assert rejects(external) == {:invalid_svg, :entity}
    end

    test "a DOCTYPE answers doctype" do
      public = """
      <?xml version="1.0" standalone="no"?>
      <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN"
        "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
      <svg xmlns="http://www.w3.org/2000/svg"/>
      """

      assert rejects(public) == {:invalid_svg, :doctype}

      assert rejects(~s|<!doctype svg SYSTEM "file:///etc/passwd">| <> svg("")) ==
               {:invalid_svg, :doctype}
    end

    test "a processing instruction other than the XML declaration answers processing_instruction" do
      stylesheet =
        ~s|<?xml version="1.0"?>\n<?xml-stylesheet href="https://evil.example/x.css"?>| <>
          svg("")

      assert rejects(stylesheet) == {:invalid_svg, :processing_instruction}
      assert rejects(svg(~s|<?php echo 1; ?>|)) == {:invalid_svg, :processing_instruction}

      assert rejects(~s|<?xml-stylesheet href="x.css"?>| <> svg("")) ==
               {:invalid_svg, :processing_instruction}
    end

    test "a byte order mark and an XML declaration are accepted" do
      output = sanitize!("\uFEFF" <> ~s|<?xml version="1.0" encoding="utf-8"?>\n| <> svg(""))
      assert output == ~s|<svg xmlns="http://www.w3.org/2000/svg"/>|
    end

    test "an XML declaration follows the production XMLDecl of XML 1.0" do
      accepted = [
        ~s|<?xml version="1.0"?>|,
        ~s|<?xml version='1.0'?>|,
        ~s|<?xml version="1.1" encoding='UTF-8' standalone="yes" ?>|,
        ~s|<?xml version = '1.0' encoding = "utf-8" standalone = 'no'?>|,
        ~s|<?xml version="1.0" standalone="yes"?>|,
        "<?xml\tversion=\"1.0\"\tstandalone='no'\t?>",
        "<?xml\r\n  version=\"1.0\"\r\n  encoding=\"UTF-8\"\r\n?>\r\n"
      ]

      for declaration <- accepted do
        assert sanitize!(declaration <> svg("")) == ~s|<svg xmlns="http://www.w3.org/2000/svg"/>|,
               declaration
      end

      rejected = [
        ~s|<?xml version="2.0"?>|,
        ~s|<?xml version="1."?>|,
        ~s|<?xml version="1.0'?>|,
        ~s|<?xml version="1.0" foo="bar"?>|,
        ~s|<?xml version="1.0" encoding="UTF-8" standalone="no" foo="bar"?>|,
        ~s|<?xml encoding="UTF-8"?>|,
        ~s|<?xml standalone="yes"?>|,
        ~s|<?xml ?>|,
        ~s|<?xml version="1.0" standalone="yes" encoding="UTF-8"?>|,
        ~s|<?xml version="1.0"standalone="yes"?>|,
        ~s|<?xml version="&#49;.0"?>|,
        ~s|<?xml version="1&#x2E;0"?>|,
        ~s|<?xml version="1.0" standalone="&#121;es"?>|,
        ~s|<?xml version="1.0" standalone="&lt;"?>|,
        ~s|<?xml version="1.0" standalone="maybe"?>|,
        ~s|<?xml version="1.0"|
      ]

      for declaration <- rejected do
        assert rejects(declaration <> svg("")) == {:invalid_svg, :parse_error}, declaration
      end

      # The encoding check comes first.
      for declaration <- [
            ~s|<?xml version="1.0" encoding="UTF&#45;8"?>|,
            ~s|<?xml version="1.0" encoding="ISO-8859-1" foo="bar"?>|
          ] do
        assert rejects(declaration <> svg("")) == {:invalid_svg, :encoding}, declaration
      end
    end
  end

  describe "parser and root" do
    test "a document that is not well-formed answers parse_error" do
      assert rejects(svg("<g>")) == {:invalid_svg, :parse_error}
      assert rejects(svg("") <> "<svg/>") == {:invalid_svg, :parse_error}
      assert rejects(svg("") <> "trailing") == {:invalid_svg, :parse_error}
      assert rejects(svg("&#0;")) == {:invalid_svg, :parse_error}
      assert rejects("") == {:invalid_svg, :parse_error}

      assert rejects(~s|<svg xmlns="http://www.w3.org/2000/svg" a="1" a="2"/>|) ==
               {:invalid_svg, :parse_error}
    end

    test "comments and white space after the root are accepted" do
      assert sanitize!(svg("") <> "\n<!-- end -->\n") ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg"/>|
    end

    test "the root must be svg in the SVG namespace" do
      assert rejects(~s|<svg/>|) == {:invalid_svg, :root}
      assert rejects(~s|<html xmlns="http://www.w3.org/1999/xhtml"/>|) == {:invalid_svg, :root}
      assert rejects(~s|<g xmlns="http://www.w3.org/2000/svg"/>|) == {:invalid_svg, :root}

      assert sanitize!(~s|<s:svg xmlns:s="http://www.w3.org/2000/svg"><s:rect/></s:svg>|) ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>|
    end

    test "an undeclared entity reference stays text" do
      assert sanitize!(svg("<text>&nbsp;</text>")) =~ "<text>&amp;nbsp;</text>"
    end
  end

  describe "bounds of the markup" do
    test "a start tag with more than 1,000 attributes answers parse_error" do
      assert sanitize!(svg("<rect#{many_attributes(1..1_000)}/>")) =~ "<rect/>"
      assert rejects(svg("<rect#{many_attributes(1..1_001)}/>")) == {:invalid_svg, :parse_error}

      assert rejects(svg(~s|<g xmlns="http://www.w3.org/2000/svg"#{many_attributes(1..1_000)}/>|)) ==
               {:invalid_svg, :parse_error}
    end

    test "attributes in comments, CDATA sections, attribute values and text do not count" do
      many = many_attributes(1..1_001)

      output =
        sanitize!(
          svg(
            "<!--<g#{many}/>--><desc><![CDATA[<g#{many}/>]]></desc>" <>
              "<text class='#{many}'>#{many}</text>"
          )
        )

      assert output =~ "<desc>&lt;g a1=&quot;&quot;"
    end

    test "an element nested deeper than 256 levels, root included, answers parse_error" do
      assert sanitize!(svg(nested("g", 255, ""))) =~ String.duplicate("<g>", 254) <> "<g/>"
      assert rejects(svg(nested("g", 256, ""))) == {:invalid_svg, :parse_error}
      assert sanitize!(svg(nested("g", 254, "<rect/>"))) =~ "<rect/>"
      assert rejects(svg(nested("g", 255, "<rect/>"))) == {:invalid_svg, :parse_error}
      assert rejects(svg(nested("a", 256, "<rect/>"))) == {:invalid_svg, :parse_error}

      # Siblings do not add up.
      assert sanitize!(svg(String.duplicate(nested("g", 200, "<rect/>"), 3))) =~ "<rect/>"
    end

    test "more than 64 namespace declarations in scope answer parse_error" do
      # svg/1 declares two namespaces on the root.
      assert sanitize!(svg("<g#{declarations(1..62)}/>")) =~ "<g/>"
      assert rejects(svg("<g#{declarations(1..63)}/>")) == {:invalid_svg, :parse_error}

      # The declarations of a closed element leave the scope.
      assert sanitize!(svg("<g#{declarations(1..31)}><g#{declarations(32..62)}/></g>")) =~ "<g/>"
      assert sanitize!(svg(String.duplicate("<g#{declarations(1..62)}></g>", 3))) =~ "<g/>"

      assert rejects(svg("<g#{declarations(1..31)}><g#{declarations(32..63)}/></g>")) ==
               {:invalid_svg, :parse_error}
    end

    test "predefined references in attribute values give the output of character references" do
      content = fn [lt, gt, amp, apos, quot] ->
        ~s|<g class="a#{lt}b#{gt}c#{amp}d#{apos}e#{apos}#{quot}f#{quot}" foo="#{amp}lt;">| <>
          ~s|<text style='font-family:#{quot}A#{quot}' xlink:title='#{apos}#{gt}#{apos}'>| <>
          "&lt;&amp;<!-- &lt; --><![CDATA[&lt;&amp;]]></text></g>"
      end

      named = sanitize!(svg(content.(~w(&lt; &gt; &amp; &apos; &quot;))))
      assert sanitize!(svg(content.(~w(&#60; &#62; &#38; &#39; &#34;)))) == named
      assert named =~ ~s|<g class="a&lt;b|

      # Text and CDATA sections keep their references.
      assert named =~ ">&lt;&amp;&amp;lt;&amp;amp;</text>"
    end
  end

  describe "work per file" do
    test "70,000 nested a elements around 139,632 g elements end in time" do
      binary = @plain_open <> nested("a", 70_000, String.duplicate("<g/>", 139_632)) <> "</svg>"
      assert timed_sanitize(binary) == {:error, {:invalid_svg, :parse_error}}
    end

    test "one rect with 98,000 attributes ends in time" do
      binary = @plain_open <> "<rect#{many_attributes(1..98_000)}/>" <> "</svg>"
      assert timed_sanitize(binary) == {:error, {:invalid_svg, :parse_error}}
    end

    test "40 levels of 1,000 namespace declarations each end in time" do
      {binary, _count} =
        fill(
          @plain_open <> String.duplicate("<g#{declarations(1..1_000)}>", 40),
          "<g/>",
          String.duplicate("</g>", 40) <> "</svg>"
        )

      assert timed_sanitize(binary) == {:error, {:invalid_svg, :parse_error}}
    end

    test "a elements nested to the depth bound around a full file of g elements" do
      # The root, 254 a elements and the g elements make 256 levels.
      {binary, count} =
        fill(
          @plain_open <> String.duplicate("<a>", 254),
          "<g/>",
          String.duplicate("</a>", 254) <> "</svg>"
        )

      assert {:ok, output, _facts} = timed_sanitize(binary)
      assert output == @plain_open <> String.duplicate("<g/>", count) <> "</svg>"
    end

    test "a full file of start tags with 1,000 attributes each" do
      {binary, count} = fill(@plain_open, "<g#{many_attributes(1..1_000)}/>", "</svg>")
      assert {:ok, output, _facts} = timed_sanitize(binary)
      assert output == @plain_open <> String.duplicate("<g/>", count) <> "</svg>"
    end

    test "a full file of prefixed elements with 64 namespace declarations in scope" do
      root =
        ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:s="http://www.w3.org/2000/svg"| <>
          declarations(1..62) <> ">"

      {binary, count} = fill(root, "<s:g/>", "</svg>")
      assert {:ok, output, _facts} = timed_sanitize(binary)
      assert output == @plain_open <> String.duplicate("<g/>", count) <> "</svg>"
    end

    test "a full file of &lt; in one attribute value" do
      {binary, _count} = fill(@plain_open <> ~s|<g class="|, "&lt;", ~s|"/></svg>|)
      assert {:ok, output, _facts} = timed_sanitize(binary)
      assert output == binary
    end

    test "a full file of &lt;, &gt; and &amp; in 1,000 attribute values per start tag" do
      value = String.duplicate("&lt;&gt;&amp;", 4)
      unit = "<g" <> Enum.map_join(1..1_000, &~s| a#{&1}="#{value}"|) <> "/>"
      {binary, count} = fill(@plain_open, unit, "</svg>")
      assert {:ok, output, _facts} = timed_sanitize(binary)
      assert output == @plain_open <> String.duplicate("<g/>", count) <> "</svg>"
    end

    test "a full file of &apos; or &quot; in one style attribute" do
      # xmerl reads &quot; inside double quotes and &apos; inside single
      # quotes in place, so each reference stands inside the other quote.
      for {quote, ref} <- [{"\"", "&apos;"}, {"'", "&quot;"}] do
        font = ref <> "A" <> ref

        {binary, _count} =
          fill(
            @plain_open <> "<g style=#{quote}font-family:#{font}",
            "," <> font,
            quote <> "/></svg>"
          )

        numeric = binary |> String.replace("&apos;", "&#39;") |> String.replace("&quot;", "&#34;")
        assert {:ok, output, facts} = timed_sanitize(binary)
        assert Svg.sanitize(numeric) == {:ok, output, facts}
      end
    end

    test "a full file of &lt; in an attribute value without its closing quote" do
      {binary, _count} = fill(@plain_open <> ~s|<g class="|, "&lt;", "")
      assert timed_sanitize(binary) == {:error, {:invalid_svg, :parse_error}}
    end

    test "a full file of &lt; in the version or standalone value of the XML declaration" do
      # xmerl reads both values as attribute values. The last head has no
      # "?>" in the whole file.
      heads = [
        {~s|<?xml version="|, ~s|"?>|},
        {~s|<?xml version="1.0" standalone="|, ~s|"?>|},
        {~s|<?xml version='1.0' encoding="UTF-8" standalone='|, ~s|'?>|},
        {~s|<?xml version="|, ""}
      ]

      for {head, close} <- heads do
        tail = if close == "", do: "", else: close <> @plain_open <> "</svg>"
        {binary, _count} = fill(head, "&lt;", tail)

        assert timed_sanitize(binary, @check_bound_us) == {:error, {:invalid_svg, :parse_error}},
               head
      end
    end

    test "a full file of &lt; in a declaration value that runs past the first ?>" do
      # xmerl reads a quoted value of the declaration up to its closing
      # quote, also past the first "?>".
      heads = [
        {~s|<?xml version="?>|, ~s|"|},
        {~s|<?xml version='1.0?>|, "'"},
        {~s|<?xml version="1.0" standalone="?>|, ~s|"|},
        {~s|<?xml version="1.0" encoding="UTF-8?>|, ~s|"|}
      ]

      for {head, quote} <- heads do
        {binary, _count} = fill(head, "&lt;", quote <> "?>" <> @plain_open <> "</svg>")

        assert timed_sanitize(binary, @check_bound_us) == {:error, {:invalid_svg, :parse_error}},
               head
      end
    end

    test "a full file of digits or white space in an XML declaration of the grammar" do
      for {head, unit, tail} <- [
            {~s|<?xml version="1.|, "0", ~s|"?>|},
            {"<?xml", "\r\n", ~s|version="1.0"?>|},
            {~s|<?xml version="1.0" standalone="yes"|, " ", "?>"}
          ] do
        {binary, _count} = fill(head, unit, tail <> @plain_open <> "</svg>")
        assert {:ok, output, _facts} = timed_sanitize(binary)
        assert output == ~s|<svg xmlns="http://www.w3.org/2000/svg"/>|
      end
    end

    test "a full file of <e or <y passes the checks for DOCTYPE and ENTITY in time" do
      # The last letters of <!DOCTYPE and <!ENTITY in one case only.
      for unit <- ["<e", "<y"] do
        {binary, _count} = fill(@plain_open, unit, "</svg>")
        assert timed_sanitize(binary, @check_bound_us) == {:error, {:invalid_svg, :parse_error}}
      end
    end

    test "a root with a full file of white space after a number in width or viewBox" do
      head = ~s|<svg xmlns="http://www.w3.org/2000/svg" height="2" width="1|
      {binary, _count} = fill(head, " ", ~s|x"/>|)
      assert {:ok, _output, %{width: nil, height: 2}} = timed_sanitize(binary)

      {binary, _count} = fill(head, " ", ~s|px "/>|)
      assert {:ok, _output, %{width: 1, height: 2}} = timed_sanitize(binary)

      viewbox = ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 3 4|
      {binary, _count} = fill(viewbox, " ", ~s|x"/>|)
      assert {:ok, _output, %{width: nil, height: nil}} = timed_sanitize(binary)
    end
  end

  describe "elements" do
    test "script, foreignObject, iframe and metadata are dropped with their content" do
      output =
        sanitize!(
          svg("""
          <script>alert(1)</script>
          <script xlink:href="data:text/javascript,alert(2)"/>
          <foreignObject width="100" height="100">
            <body xmlns="http://www.w3.org/1999/xhtml"><script>alert(3)</script></body>
          </foreignObject>
          <iframe src="javascript:alert(4)"/>
          <metadata><title>kept out</title></metadata>
          <rect width="1" height="1"/>
          """)
        )

      refute output =~ "script"
      refute output =~ "alert"
      refute output =~ "foreignObject"
      refute output =~ "iframe"
      refute output =~ "kept out"
      assert output =~ ~s|<rect width="1" height="1"/>|
    end

    test "animation elements and mpath are dropped" do
      output =
        sanitize!(
          svg("""
          <a><animate attributeName="href" values="javascript:alert(1)"/><text>link</text></a>
          <set attributeName="onmouseover" to="alert(2)"/>
          <rect><animateTransform attributeName="transform" type="rotate"/></rect>
          <circle><animateMotion dur="1s"><mpath xlink:href="#p"/></animateMotion></circle>
          <path><animateColor attributeName="fill"/></path>
          """)
        )

      for name <- ~w(animate set animateTransform animateMotion animateColor mpath alert) do
        refute output =~ name
      end

      assert output =~ "<text>link</text>"
      assert output =~ "<rect/>"
    end

    test "a is unwrapped and keeps its children in place" do
      output =
        sanitize!(
          svg(
            ~s|<g><a xlink:href="javascript:alert(1)" href="https://evil.example/">| <>
              ~s|<rect/>t<a><circle/></a></a><path/></g>|
          )
        )

      assert output ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg"><g><rect/>t<circle/><path/></g></svg>|
    end

    test "elements outside the SVG namespace or the allowlist are dropped" do
      output =
        sanitize!(
          svg("""
          <html:div xmlns:html="http://www.w3.org/1999/xhtml"><rect/></html:div>
          <g xmlns="urn:other"><rect/></g>
          <unknown><rect id="inner"/></unknown>
          <clippath id="lower"/>
          <cursor xlink:href="https://evil.example/c.png"/>
          <font-face font-family="x"/>
          <discard/>
          <clipPath id="kept"/>
          """)
        )

      refute output =~ "div"
      refute output =~ "inner"
      refute output =~ "lower"
      refute output =~ "cursor"
      refute output =~ "font-face"
      refute output =~ "discard"
      assert output =~ ~s|<clipPath id="kept"/>|
    end

    test "an image element rejects the file, also inside a dropped subtree" do
      jpeg = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAg="

      assert rejects(svg(~s|<image href="#{jpeg}" width="10" height="10"/>|)) ==
               {:invalid_svg, :embedded_image}

      assert rejects(
               svg(~s|<defs><pattern id="p"><image xlink:href="photo.jpg"/></pattern></defs>|)
             ) ==
               {:invalid_svg, :embedded_image}

      assert rejects(svg(~s|<metadata><image href="#{jpeg}"/></metadata>|)) ==
               {:invalid_svg, :embedded_image}
    end
  end

  describe "attributes" do
    test "event handlers and attributes outside the allowlist are dropped" do
      output =
        sanitize!(
          ~s|<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)" ONLOAD="alert(2)" | <>
            ~s|baseProfile="full"><rect onclick="alert(3)" onmouseover="alert(4)" | <>
            ~s|viewbox="0 0 1 1" fill="red" data-x="1"/></svg>|
        )

      assert output == ~s|<svg xmlns="http://www.w3.org/2000/svg"><rect fill="red"/></svg>|
    end

    test "prefixed attributes stay only as the xlink and xml names of attrs.xml" do
      output =
        sanitize!(
          ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xl="http://www.w3.org/1999/xlink" | <>
            ~s|xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">| <>
            ~s|<g inkscape:label="Layer" xl:title="Group" xl:show="new" xml:space="preserve" | <>
            ~s|xml:lang="en" xml:id="g1" p:fill="red" svg:fill="red"/></svg>|
        )

      assert output ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">| <>
                 ~s|<g xlink:title="Group" xml:space="preserve" xml:id="g1"/></svg>|
    end

    test "href and xlink:href stay only as an internal reference" do
      output =
        sanitize!(
          svg("""
          <use href="#a"/>
          <use xlink:href="#b-1"/>
          <use href="https://evil.example/sprite.svg#a"/>
          <use xlink:href="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=#x"/>
          <use href="sprite.svg#a"/>
          <use href="#xpointer(id('a'))"/>
          <feImage href="https://evil.example/x.png"/>
          <linearGradient id="g2" xlink:href="#g1"/>
          <textPath href="javascript:alert(1)">t</textPath>
          """)
        )

      assert output =~ ~s|<use href="#a"/>|
      assert output =~ ~s|<use xlink:href="#b-1"/>|
      assert output =~ ~s|<linearGradient id="g2" xlink:href="#g1"/>|
      assert output =~ "<feImage/>"
      assert output =~ "<textPath>t</textPath>"
      refute output =~ "evil"
      refute output =~ "data:"
      refute output =~ "sprite"
      refute output =~ "xpointer"
      refute output =~ "javascript"
    end

    test "a second attribute with the same output name is dropped" do
      output =
        sanitize!(
          ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:a="http://www.w3.org/1999/xlink" | <>
            ~s|xmlns:b="http://www.w3.org/1999/xlink"><use a:href="#one" b:href="#two"/></svg>|
        )

      assert output =~ ~s|<use xlink:href="#one"/>|
      refute output =~ "#two"
    end
  end

  describe "CSS" do
    test "url() other than an internal reference rejects the file in every attribute" do
      for attribute <- ~w(fill stroke filter mask clip-path marker-start marker-mid marker-end) do
        assert rejects(svg(~s|<rect #{attribute}="url(https://evil.example/p.svg#p)"/>|)) ==
                 {:invalid_svg, :css},
               attribute
      end

      assert rejects(svg(~s|<rect fill="URL( 'data:image/png;base64,AAAA' )"/>|)) ==
               {:invalid_svg, :css}

      assert rejects(svg(~s|<rect style="fill: url(other.svg#p)"/>|)) == {:invalid_svg, :css}
      assert rejects(svg(~s|<rect style="cursor: url(c.png), auto"/>|)) == {:invalid_svg, :css}

      assert sanitize!(
               svg(
                 ~s|<rect fill="url(#p)" style="filter: url( '#f' ); mask: url(&quot;#m&quot;)"/>|
               )
             ) =~ "url(#p)"
    end

    test "resource functions, @import and backslashes reject the file" do
      rejected = [
        ~s|<rect style="background-image: image-set('a.png' 1x)"/>|,
        ~s|<rect style="background: -webkit-image-set(url(#a) 1x)"/>|,
        ~s|<rect style="background: image('a.png')"/>|,
        ~s|<rect style="background: cross-fade(url(#a), url(#b), 50%)"/>|,
        ~s|<rect style="background: -moz-element(#a)"/>|,
        ~s|<rect style="background: src('a.png')"/>|,
        ~s|<rect style="width: expression(alert(1))"/>|,
        ~s|<rect style="fill: u\\72l(https://evil.example/)"/>|,
        ~s|<rect class="a\\b"/>|,
        ~s|<style>@import url(https://evil.example/x.css);</style>|,
        ~s|<style>@import 'x.css';</style>|,
        ~s|<style>rect { fill: url(https://evil.example/p) }</style>|,
        ~s|<style><![CDATA[rect { behavior: url(x.htc) }]]></style>|,
        ~s|<style>@font-face { font-family: x; src: url(data:font/woff2;base64,AAAA) }</style>|,
        ~s|<style>rect { -moz-binding: url(x.xml#b) }</style>|
      ]

      for content <- rejected do
        assert rejects(svg(content)) == {:invalid_svg, :css}, content
      end
    end

    test "CSS comments do not hide a rejected function" do
      assert rejects(svg(~s|<style>rect { fill: url/**/(x) }</style>|)) == {:invalid_svg, :css}
      assert rejects(svg(~s|<style>/* a */ @import 'x.css';</style>|)) == {:invalid_svg, :css}
    end

    test "keyframes and the animation and transition properties answer animation" do
      rejected = [
        ~s|<style>@keyframes spin { to { transform: rotate(1turn) } }</style>|,
        ~s|<style>@-webkit-keyframes spin { }</style>|,
        ~s|<style>rect{animation:spin 1s infinite}</style>|,
        ~s|<style>rect { -webkit-animation-name: spin }</style>|,
        ~s|<style>rect { transition: fill 1s }</style>|,
        ~s|<rect style="animation-duration: 1s"/>|,
        ~s|<rect style="fill: red; TRANSITION-property: fill"/>|,
        ~s|<rect style="animation/**/: spin 1s"/>|
      ]

      for content <- rejected do
        assert rejects(svg(content)) == {:invalid_svg, :animation}, content
      end
    end

    test "a comment start inside a string hides no rule" do
      in_style = [
        {~s|svg{content:"/*"}@keyframes spin{to{transform:rotate(360deg)}}| <>
           ~s|rect{animation:spin 1s infinite;content:"*/"}|, :animation},
        {~s|svg{content:'/*'}rect{fill:url(https://evil.example/p.svg#p)}svg{content:'*/'}|,
         :css},
        {~s|svg{content:"/*"}@import url(https://evil.example/x.css);svg{content:"*/"}|, :css},
        {~s|svg{content:"/*"}@import 'x.css';svg{content:"*/"}|, :css},
        {~s|svg{content:"/*"}@font-face{font-family:x;src:url(data:font/woff2;base64,AAAA)}| <>
           ~s|svg{content:"*/"}|, :css},
        {~s|svg{content:"/*'"}rect{transition:fill 2s}svg{content:'*/"'}|, :animation}
      ]

      for {css, tag} <- in_style do
        assert rejects(svg("<style>#{Interop.xml_escape(css)}</style>")) == {:invalid_svg, tag},
               css
      end

      in_attributes = [
        {~s|style="content:'/*';animation:spin 1s infinite;content:'*/'"|, :animation},
        {~s|style="content:&quot;/*&quot;;fill:url(https://evil.example/p);content:&quot;*/&quot;"|,
         :css},
        {~s|fill="url(#a) '/*' url(https://evil.example/p) '*/'"|, :css}
      ]

      for {attribute, tag} <- in_attributes do
        assert rejects(svg("<rect #{attribute}/>")) == {:invalid_svg, tag}, attribute
      end
    end

    test "a backslash rejects the file also inside a string or a comment" do
      for css <- [~s|rect{content:"\\2f*"}|, ~s|rect{fill:red}/* \\ */|, ~s|rect{fill:r\\65 d}|] do
        assert rejects(svg("<style>#{css}</style>")) == {:invalid_svg, :css}, css
      end
    end

    test "an unquoted url() is one token up to its parenthesis" do
      # The tokenizer reads everything up to ")" as one URL token, "#a/*" and
      # the bad URL "#a\"" alike, so the rest is live CSS.
      rejected = [
        ~s|<style>rect{fill:url(#a/*)}@keyframes x{}rect{animation:x 1s}/**/</style>|,
        ~s|<style>rect{fill:url(#a")}@keyframes x{}rect{animation:x 1s}"</style>|
      ]

      for content <- rejected do
        assert rejects(svg(content)) == {:invalid_svg, :css}, content
      end

      output =
        sanitize!(svg(~s|<rect fill="url( #a )" stroke="url( '#b' )" style="fill:URL(#c)"/>|))

      assert output =~ ~s|fill="url( #a )"|
    end

    test "animation and transition count after the end of a nested rule and in a selector" do
      rejected = [
        ~s|<style>rect{fill:red;&amp;:hover{fill:blue}transition:fill 2s}</style>|,
        ~s|<style>rect{&amp;:hover{fill:blue}animation-name:spin}</style>|,
        ~s|<style>rect{&amp;:hover{fill:blue}/* x */-webkit-Transition-Duration :1s}</style>|,
        ~s|<style>rect{fill:red}g{&amp;:hover{fill:blue}}rect{x:1}\nanimation:spin 1s</style>|,
        ~s|<rect style="fill:red;&amp;:hover{fill:blue}transition:fill 2s"/>|,
        ~s|<style>.transition:hover{fill:red}</style>|
      ]

      for content <- rejected do
        assert rejects(svg(content)) == {:invalid_svg, :animation}, content
      end
    end

    test "a word inside a string or a longer identifier is no property and no function" do
      output =
        sanitize!(
          svg(
            ~s|<style>text{font-family:"transition: x, url(y), @import /* z"}| <>
              ~s|.a{--transition:x;view-transition-name:b}</style>| <>
              ~s|<text style="font-family:'animation:a'" fill="url('#g')">t</text>|
          )
        )

      assert output =~ "transition: x, url(y), @import /* z"
      assert output =~ "view-transition-name:b"
      assert output =~ ~s|style="font-family:&apos;animation:a&apos;"|
    end

    test "an unterminated string, comment or url() rejects the file" do
      rejected = [
        ~s|<style>text{font-family:"a}</style>|,
        ~s|<style>text{font-family:'a}</style>|,
        ~s|<style>text{content:"a\nb"}</style>|,
        ~s|<style>text{content:'a&#13;b'}</style>|,
        ~s|<style>rect{fill:red} /* note</style>|,
        ~s|<style>rect{fill:red} /*/</style>|,
        ~s|<rect style="fill:red /* note"/>|,
        ~s|<rect fill="url(#a"/>|,
        ~s|<text font-family="'Font"/>|,
        ~s|<g xlink:title="Don't"/>|
      ]

      for content <- rejected do
        assert rejects(svg(content)) == {:invalid_svg, :css}, content
      end
    end

    test "a style element without resources and motion stays, escaped" do
      output = sanitize!(svg("<style>.a > .b { fill: #000 } /* note */</style>"))
      assert output =~ "<style>.a &gt; .b { fill: #000 } /* note */</style>"
    end

    test "a style element keeps only its own text" do
      output = sanitize!(svg(~s|<style>.a { fill: red }<g>@import url(x.css);</g></style>|))
      assert output =~ "<style>.a { fill: red }</style>"

      assert rejects(svg(~s|<style><image href="x.png"/></style>|)) ==
               {:invalid_svg, :embedded_image}
    end

    test "dropped attributes and dropped elements are not checked" do
      assert sanitize!(
               ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:i="urn:i" i:file="C:\\a\\b.png">| <>
                 ~s|<metadata><style>@import url(x.css);</style></metadata></svg>|
             ) == ~s|<svg xmlns="http://www.w3.org/2000/svg"/>|
    end
  end

  describe "output" do
    test "text and attribute values are escaped, also white space that a parser normalizes" do
      output =
        sanitize!(
          svg(
            ~s|<text x="1" class="a&#10;b&#9;c&#13;d" font-family="'A &amp; B' &quot;C&quot;">| <>
              ~s|a &lt; b &amp; "c" &#13;<![CDATA[<d> & e]]></text>|
          )
        )

      assert output =~
               ~s|<text x="1" class="a&#10;b&#9;c&#13;d" font-family="&apos;A &amp; B&apos; &quot;C&quot;">| <>
                 ~s|a &lt; b &amp; &quot;c&quot; &#13;&lt;d&gt; &amp; e</text>|
    end

    test "comments are dropped and the XLink namespace is declared only when used" do
      assert sanitize!(svg("<!-- note --><g/>")) ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg"><g/></svg>|

      assert sanitize!(svg(~s|<g><use xlink:href="#a"/></g>|)) ==
               ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">| <>
                 ~s|<g><use xlink:href="#a"/></g></svg>|
    end

    test "an Inkscape sample keeps viewBox, clipPath, the gradient reference and the clone" do
      source = File.read!(Path.join(@fixtures, "inkscape.svg"))
      assert {:ok, output, facts} = Svg.sanitize(source)
      assert Svg.sanitize(output) == {:ok, output, facts}

      assert facts == %{width: 64, height: 32}
      assert output =~ ~s|viewBox="0 0 64 32"|
      assert output =~ ~s|<clipPath clipPathUnits="userSpaceOnUse" id="clipPath1">|
      assert output =~ ~s|xlink:href="#linearGradient2"|
      assert output =~ ~s|clip-path="url(#clipPath1)"|
      assert output =~ ~s|style="fill:url(#linearGradient3);stroke:#000000;stroke-width:0.5"|
      assert output =~ ~s|<use x="0" y="0" xlink:href="#rect1"|
      assert output =~ "Check &amp; go"

      for name <- ~w(inkscape sodipodi metadata rdf:RDF Example) do
        refute output =~ name
      end
    end

    test "an Illustrator sample keeps viewBox, clipPath, the style and the gradient reference" do
      source = File.read!(Path.join(@fixtures, "illustrator.svg"))
      assert {:ok, output, facts} = Svg.sanitize(source)
      assert Svg.sanitize(output) == {:ok, output, facts}

      assert facts == %{width: 100, height: 50}
      assert output =~ ~s|viewBox="0 0 100 50"|
      assert output =~ ~s|<clipPath id="SVGID_2_">|
      assert output =~ ~s|<use xlink:href="#SVGID_1_" style="overflow:visible;"/>|
      assert output =~ ~s|<linearGradient id="SVGID_4_" xlink:href="#SVGID_3_"|
      assert output =~ ".st0{clip-path:url(#SVGID_2_);fill:url(#SVGID_4_);}"
      assert output =~ ~s|xml:space="preserve"|
      refute output =~ "Illustrator"
    end
  end

  describe "facts" do
    test "width and height without a unit or in px, rounded" do
      assert facts(~s|width="120" height="80px"|) == %{width: 120, height: 80}
      assert facts(~s|width=" 10.5 " height="1e2"|) == %{width: 11, height: 100}
      assert facts(~s|width=".4" height="2."|) == %{width: 1, height: 2}
    end

    test "viewBox gives the missing dimensions and the aspect ratio" do
      assert facts(~s|viewBox="0 0 300 150"|) == %{width: 300, height: 150}
      assert facts(~s|viewBox="-5,-5,10.4,20"|) == %{width: 10, height: 20}
      assert facts(~s|width="100%" height="100%" viewBox="0 0 30 20"|) == %{width: 30, height: 20}
      assert facts(~s|width="60" viewBox="0 0 30 20"|) == %{width: 60, height: 40}
      assert facts(~s|height="10" viewBox="0 0 30 20"|) == %{width: 15, height: 10}

      assert facts(~s|width="20mm" height="10mm" viewBox="0 0 200 100"|) == %{
               width: 200,
               height: 100
             }
    end

    test "dimensions that cannot be determined are nil" do
      assert facts("") == %{width: nil, height: nil}
      assert facts(~s|width="50%"|) == %{width: nil, height: nil}
      assert facts(~s|width="40"|) == %{width: 40, height: nil}
      assert facts(~s|viewBox="0 0 0 10"|) == %{width: nil, height: nil}
      assert facts(~s|width="-5" height="5em"|) == %{width: nil, height: nil}
      assert facts(~s|width="1e400" height="3000000000"|) == %{width: nil, height: nil}
    end
  end

  describe "idempotence" do
    property "a second sanitize of the output gives the same bytes and facts" do
      check all(document <- document(), max_runs: 300) do
        assert {:ok, output, facts} = Svg.sanitize(document)
        assert Svg.sanitize(output) == {:ok, output, facts}

        for marker <- ~w(script foreignObject onclick onload javascript evil inkscape animate) do
          refute output =~ marker
        end
      end
    end
  end

  ## Generators

  # Names of allowed, unwrapped and dropped elements.
  @element_names ~w(g rect circle path text tspan defs linearGradient stop clipPath use
                    style title svg a script foreignObject metadata animate unknownThing)

  # Text without "(", ":", "@", "\\", "/" and "]" outside strings, so no
  # generated text forms a CSS function, a property, an at-rule, an escape,
  # a comment or the end of CDATA. Quotes come in pairs around a string
  # without a line break, which may hold "(", ":", "@", "/" and "*" and the
  # other quote, so every text is CSS whose strings end and hide these
  # characters from the checks.
  @alphabet ~w(a b c x y z 0 1 . - _ < > & é € 😀) ++ [" ", " ", "\n", "\t", "\r"]
  @string_alphabet ~w[a x 0 . - < > & é / * ( ) : ; @ { }] ++ [" ", "\t"]

  defp document do
    gen all(
          attributes <- attributes(),
          children <- list_of(svg_node(), max_length: 4)
        ) do
      ~s|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" | <>
        ~s|xmlns:xl="http://www.w3.org/1999/xlink" xmlns:inkscape="urn:inkscape"| <>
        Enum.join(attributes) <> ">" <> Enum.join(children) <> "</svg>"
    end
  end

  defp svg_node do
    tree(leaf(), fn child ->
      gen all(
            name <- member_of(@element_names),
            attributes <- attributes(),
            children <- list_of(child, max_length: 3)
          ) do
        "<#{name}#{Enum.join(attributes)}>#{Enum.join(children)}</#{name}>"
      end
    end)
  end

  defp leaf do
    one_of([
      map(text(), &escape_text/1),
      map(text(), &("<![CDATA[" <> &1 <> "]]>")),
      map(text(), &("<!--" <> String.replace(&1, "-", "") <> "-->")),
      map(member_of(@element_names), &"<#{&1}/>")
    ])
  end

  defp attributes do
    # A repeated name would make the document malformed, so only its first
    # occurrence stays.
    list_of(attribute(), max_length: 4)
    |> map(fn attributes ->
      attributes
      |> Enum.uniq_by(fn {name, _value} -> name end)
      |> Enum.map(fn {name, value} -> ~s| #{name}="#{value}"| end)
    end)
  end

  defp attribute do
    one_of([
      tuple(
        {member_of(
           ~w(id class fill stroke-width style transform onclick onload inkscape:label foo)
         ), map(text(), &escape_attribute/1)}
      ),
      tuple(
        {member_of(~w(href xlink:href xl:href)),
         member_of(["#a", "#b-1", "https://evil.example/x.svg#a", "javascript.alert", ""])}
      ),
      tuple({constant("xml:space"), member_of(["preserve", "default"])}),
      tuple({member_of(~w(width height)), member_of(["10", "2.5px", "50%", "1e2", "x"])}),
      tuple({constant("viewBox"), member_of(["0 0 10 20", "0,0,3,4", "0 0 0 0", "bad"])})
    ])
  end

  defp text do
    map(list_of(one_of([member_of(@alphabet), css_string()]), max_length: 12), &Enum.join/1)
  end

  defp css_string do
    gen all(
          {quote, other} <- member_of([{~s("), "'"}, {"'", ~s(")}]),
          chars <- list_of(member_of([other | @string_alphabet]), max_length: 6)
        ) do
      quote <> Enum.join(chars) <> quote
    end
  end

  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\r", "&#13;")
  end

  defp escape_attribute(text) do
    text
    |> escape_text()
    |> String.replace("\"", "&quot;")
    |> String.replace("\n", "&#10;")
    |> String.replace("\t", "&#x9;")
  end
end
