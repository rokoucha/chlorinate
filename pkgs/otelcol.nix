{
  stdenvNoCC,
  fetchurl,
}:
let
  # renovate: datasource=github-release-attachments depName=rokoucha/container-images versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260730.035456";
  sourceBinaryName = "otelcol-chlorine-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "otelcol";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rokoucha/container-images/releases/download/${version}/${sourceBinaryName}.tar.gz";
    hash = "sha256:54fb5804842d11362672b73c47586a960b162456a7a5f7919445b653e31f79ac";
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
