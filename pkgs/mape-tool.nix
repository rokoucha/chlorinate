{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20261117.155314";
in
stdenvNoCC.mkDerivation {
  pname = "mape-tool";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/mape-tool/releases/download/${version}/mape-tool-linux-amd64";
    hash = "sha256:d3e5098f24770f21e6534a80783b2bf1fdbc2c1aa6d59a66a5fe0a2927b97052";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 "$src" "$out/bin/mape-tool"
  '';
}
