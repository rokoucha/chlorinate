{ lib, stdenv, fetchurl, libpcap }:

stdenv.mkDerivation {
  pname = "host-sflow";
  version = "2.1.26-1";
  src = fetchurl {
    name = "host-sflow-2.1.26-1.tar.gz";
    url = "https://codeload.github.com/sflow/host-sflow/tar.gz/refs/tags/v2.1.26-1";
    sha256 = "611f18c1f6ebeb14e3069a5e02b762bbfd85f8ef3e6593d5fe3a6a3eacb070e3";
  };
  buildInputs = [ libpcap ];
  postPatch = ''
    substituteInPlace src/Linux/Makefile --replace-fail 'CLANG=clang' 'CLANG=cc'
  '';
  makeFlags = [ "FEATURES=PCAP" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 src/Linux/hsflowd $out/bin/hsflowd
    mkdir -p $out/lib/hsflowd
    cp src/Linux/*.so $out/lib/hsflowd/
    runHook postInstall
  '';
  meta = {
    description = "Host sFlow agent with kernel packet sampling through libpcap";
    homepage = "https://sflow.net/";
    platforms = lib.platforms.linux;
  };
}
