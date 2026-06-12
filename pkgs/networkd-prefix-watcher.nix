{
  buildGoModule,
  fetchFromGitHub,
}:
let
  # renovate: datasource=github-tags depName=rokoucha/networkd-prefix-watcher versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260612.145210";
in
buildGoModule {
  pname = "networkd-prefix-watcher";
  inherit version;

  src = fetchFromGitHub {
    owner = "rokoucha";
    repo = "networkd-prefix-watcher";
    rev = version;
    hash = "sha256-QEKjuX4QLsAINc/j2zzjbgrpCAdURJI2tw+BrrfG2Zc=";
  };

  vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";
}
