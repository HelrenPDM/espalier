let
  pkgs = import (fetchTarball {
    # nixos-26.05, resolved 2026-10-07
    url = "https://github.com/NixOS/nixpkgs/archive/b25309931cfda5f0b8805f462a29897eeae50168.tar.gz";
    sha256 = "1svxsx57g7x76cjsgpw5vvg0l194mshk57fdvdqqgd5xdy0ari58";
  }) { };
  beam = pkgs.beam28Packages;
in
pkgs.mkShell {
  name = "espalier-shell";
  nativeBuildInputs = [
    beam.erlang
    beam.elixir_1_20
    pkgs.nodejs_24
    pkgs.postgresql_18
    pkgs.plantuml
    pkgs.graphviz
    pkgs.gitleaks
    pkgs.gnumake
    pkgs.openssl
  ] ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools;

  shellHook = ''
    export MIX_HOME="$PWD/.nix-mix"
    export HEX_HOME="$PWD/.nix-hex"
    export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
    export ERL_AFLAGS="-kernel shell_history enabled"
    export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
    export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
  '';
}
