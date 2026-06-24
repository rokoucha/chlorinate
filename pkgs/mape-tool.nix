{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260624.175323";
in
stdenvNoCC.mkDerivation {
  pname = "mape-tool";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/mape-tool/releases/download/${version}/mape-tool-linux-amd64";
    hash = "sha256:5bff86e87653a5a9b7bbad0c224047a25be63d31c9c506b43cecbe6e0ccadaf0";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 "$src" "$out/bin/mape-tool"
  '';
}
