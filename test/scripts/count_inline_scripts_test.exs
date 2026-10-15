defmodule Espalier.Scripts.CountInlineScriptsTest do
  @moduledoc """
  `scripts/count-inline-scripts.sh`, which `scripts/check-headers.sh` runs
  on the `index.html` of the SPA (task 0017, step 5): every script tag
  without a `src` attribute counts on its own.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../scripts/count-inline-scripts.sh", __DIR__)

  defp count(html, dir) do
    file = Path.join(dir, "index.html")
    File.write!(file, html)
    {output, 0} = System.cmd("sh", [@script, file])
    String.trim(output)
  end

  test "an external script and an inline script on one line count as one inline script",
       %{tmp_dir: dir} do
    assert count(~s|<script src="/assets/app.js"></script><script>alert(1)</script>\n|, dir) ==
             "1"
  end

  test "the tags of a Vite build count as external", %{tmp_dir: dir} do
    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <script type="module" crossorigin src="/spa/assets/index-D6JUmKuY.js"></script>
        <link rel="stylesheet" crossorigin href="/spa/assets/index-Y9s7HUIS.css">
      </head>
      <body><div id="root"></div><noscript>JavaScript is off.</noscript></body>
    </html>
    """

    assert count(html, dir) == "0"
  end

  test "each tag counts on its own, whatever its case or line breaks", %{tmp_dir: dir} do
    assert count("<SCRIPT>run()</SCRIPT>", dir) == "1"
    assert count(~s|<script\n  type="module"\n  src="/a.js"></script>|, dir) == "0"
    assert count(~s|<script data-src="/a.js">run()</script>|, dir) == "1"
    assert count("<script>if (a<b) { run() }</script><script>run()</script>", dir) == "2"
    assert count("<p>no script</p>", dir) == "0"
  end
end
