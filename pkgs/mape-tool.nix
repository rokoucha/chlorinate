{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260716.193442";
in
stdenvNoCC.mkDerivation {
  pname = "mape-tool";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/mape-tool/releases/download/${version}/mape-tool-linux-amd64";
    hash = "sha256:a9e4cbc83d9cfe3eb0e37f00eb13aaf9c6f38b420b071a1ee8b5630f32670011";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 "$src" "$out/bin/mape-tool"
  '';
}
