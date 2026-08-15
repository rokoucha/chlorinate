{
  buildGoModule,
  fetchFromGitHub,
}:
let
  # renovate: datasource=github-tags depName=rokoucha/cloudflare-ddns versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260814.071357";
in
buildGoModule {
  pname = "cloudflare-ddns";
  inherit version;

  src = fetchFromGitHub {
    owner = "rokoucha";
    repo = "cloudflare-ddns";
    rev = version;
    hash = "sha256-Cp+OurtOY5v+GKDuSVwfqsrz5hp83upuooQzYYVCE1M=";
  };

  vendorHash = "sha256-/8g3nt4SbSgDXe0lznZNJ6YDGhfpKmXqB27w6C407nM=";
}
