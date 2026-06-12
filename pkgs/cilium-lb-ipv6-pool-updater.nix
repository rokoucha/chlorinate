{
  buildGoModule,
  fetchFromGitHub,
}:
let
  # renovate: datasource=github-tags depName=rokoucha/cilium-lb-ipv6-pool-updater versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260612.163630";
in
buildGoModule {
  pname = "cilium-lb-ipv6-pool-updater";
  inherit version;

  src = fetchFromGitHub {
    owner = "rokoucha";
    repo = "cilium-lb-ipv6-pool-updater";
    rev = version;
    hash = "sha256-bTYWD1jF3JtSMJwjvrPFEFe9d4GetdlTQRcY3hoksR8=";
  };

  vendorHash = "sha256-rDbjrDcc10JyL9vwCq7bzSIxkGcNFZ0ExbXd5pb7ogg=";
}
