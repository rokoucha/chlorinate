{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/container-images versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260716.153940";
  sourceBinaryName = "otelcol-chlorine-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "otelcol";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/container-images/releases/download/${version}/${sourceBinaryName}.tar.gz";
    hash = "sha256:afbbb456b5a4ce2bb5c5716fefcd8c44bba8d0280f1ee2dbf6deaf7100235ca8";
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
