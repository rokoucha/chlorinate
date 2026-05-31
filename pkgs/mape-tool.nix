{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260527.230833";
in
stdenvNoCC.mkDerivation {
  pname = "mape-tool";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/mape-tool/releases/download/${version}/mape-tool-linux-amd64";
    hash = "sha256:195217920b900e82475200077e8918b5e5228dffb294120e91bff6e62c8235ea";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 "$src" "$out/bin/mape-tool"
  '';
}
