{
  buildGoModule,
  fetchFromGitHub,
}:
let
  # renovate: datasource=github-tags depName=rokoucha/cloudflare-ddns versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260527.153424";
in
buildGoModule {
  pname = "cloudflare-ddns";
  inherit version;

  src = fetchFromGitHub {
    owner = "rokoucha";
    repo = "cloudflare-ddns";
    rev = version;
    hash = "sha256-Rft6hJy5Qs7Kqlc+zWFryHw+mxmdcRS9lvbzAR1e98o=";
  };

  vendorHash = "sha256-H6ilB9CDq71oPQzyVWm/fQbKlsHG+wyQPQ5HOHftXlU=";
}
