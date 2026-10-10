defmodule Espalier.Catalog.SpdxTest do
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{Loader, Spdx, Validator}

  describe "expression?/1" do
    test "accepts license ids of the list, in any case" do
      for license <- ["CC0-1.0", "MIT", "Apache-2.0", "cc0-1.0", "apache-2.0", "GPL-2.0-only"] do
        assert Spdx.expression?(license), license
      end
    end

    test "accepts compound expressions with AND, OR, WITH and parentheses" do
      for license <- [
            "MIT OR Apache-2.0",
            "(MIT OR Apache-2.0) AND BSD-3-Clause",
            "MIT AND (Apache-2.0 OR BSD-3-Clause)",
            "((MIT))",
            "GPL-2.0-or-later WITH Classpath-exception-2.0",
            "GPL-2.0-only WITH Classpath-exception-2.0 OR MIT",
            "MIT  OR  Apache-2.0",
            "LGPL-2.1-only OR MIT AND BSD-3-Clause"
          ] do
        assert Spdx.expression?(license), license
      end
    end

    test "accepts a license id with +, deprecated ids and references to other licenses" do
      for license <- [
            "GPL-2.0+",
            "LGPL-2.1+ OR MIT",
            "LicenseRef-proprietary",
            "DocumentRef-spdx-tool-1.2:LicenseRef-MIT-Style-2",
            "Apache-2.0 WITH AdditionRef-my-exception",
            "MIT OR LicenseRef-internal.v1"
          ] do
        assert Spdx.expression?(license), license
      end
    end

    test "rejects ids that are not on the list and expressions that break the grammar" do
      for license <- [
            "",
            " ",
            "proprietary",
            "MIT OR",
            "OR MIT",
            "MIT Apache-2.0",
            "(MIT",
            "MIT)",
            "()",
            "MIT AND (Apache-2.0",
            "mit or apache-2.0",
            "MIT with Classpath-exception-2.0",
            "MIT WITH",
            "MIT WITH MIT",
            "MIT WITH Unknown-exception",
            "(MIT OR Apache-2.0) WITH Classpath-exception-2.0",
            "GPL-2.0 +",
            "GPL-2.0++",
            "LicenseRef-",
            "LicenseRef-a+",
            "DocumentRef-x:MIT",
            "MIT/Apache-2.0",
            "MIT,Apache-2.0",
            "AND"
          ] do
        refute Spdx.expression?(license), inspect(license)
      end
    end

    test "names the version of the SPDX License List" do
      assert Spdx.list_version() =~ ~r/\A\d+\.\d+(\.\d+)?\z/
    end
  end

  describe "the license of pack.yaml" do
    test "takes an SPDX expression and rejects other text with the file and the line" do
      pack = copy_pack!("minimal")
      line = line_of!(pack, "pack.yaml", "license:")
      license_line = ~r/^license: .*$/m

      write!(
        pack,
        "pack.yaml",
        Regex.replace(
          license_line,
          read!(pack, "pack.yaml"),
          "license: (MIT OR Apache-2.0) AND CC0-1.0"
        )
      )

      assert {:ok, loaded} = Loader.load(pack)

      assert %{errors: [], payload: %{"license" => "(MIT OR Apache-2.0) AND CC0-1.0"}} =
               Validator.run(loaded)

      write!(
        pack,
        "pack.yaml",
        Regex.replace(license_line, read!(pack, "pack.yaml"), "license: proprietary")
      )

      assert {:ok, loaded} = Loader.load(pack)

      assert [%{file: "pack.yaml", line: ^line, message: message}] = Validator.run(loaded).errors
      assert message =~ "`license` must be an SPDX license expression"
      assert message =~ Spdx.list_version()
    end
  end
end
