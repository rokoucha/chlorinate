{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/container-images versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260721.160109";
  sourceBinaryName = "otelcol-chlorine-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "otelcol";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/container-images/releases/download/${version}/${sourceBinaryName}.tar.gz";
    hash = "sha256:950d39089d6eb83efc379e26175adc2103ecc4c1e60ec38e8be3b4b08a6984d9";
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
