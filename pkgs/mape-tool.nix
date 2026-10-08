{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20261008.084120";
in
stdenvNoCC.mkDerivation {
  pname = "mape-tool";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/mape-tool/releases/download/${version}/mape-tool-linux-amd64";
    hash = "sha256:92689919bbd41f5adbdfaacc234f1cbe6411d7ed793b423e29da8efd8b896eb0";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 "$src" "$out/bin/mape-tool"
  '';
}
