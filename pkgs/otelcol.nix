{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/container-images versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260725.100922";
  sourceBinaryName = "otelcol-chlorine-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "otelcol";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/container-images/releases/download/${version}/${sourceBinaryName}.tar.gz";
    hash = "sha256:4def68124cadddaa684c00ec8b7508e79b903bd3a1911c4907e481f89f24e7ea";
  };

  unpackPhase = ''
    runHook preUnpack

    tar -xzf "$src"

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 "${sourceBinaryName}" "$out/bin/otelcol"

    runHook postInstall
  '';

  meta.mainProgram = "otelcol";
}
