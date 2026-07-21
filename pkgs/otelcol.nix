{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/container-images versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260722.060604";
  sourceBinaryName = "otelcol-chlorine-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "otelcol";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/container-images/releases/download/${version}/${sourceBinaryName}.tar.gz";
    hash = "sha256:3312fa4e614da029e1296770d977e79ebebf1b8155f6481856dddf06e6537ed4";
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
