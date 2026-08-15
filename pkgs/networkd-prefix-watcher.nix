{
  buildGoModule,
  fetchFromGitHub,
}:
let
  # renovate: datasource=github-tags depName=rokoucha/networkd-prefix-watcher versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
  version = "20260721.143524";
in
buildGoModule {
  pname = "networkd-prefix-watcher";
  inherit version;

  src = fetchFromGitHub {
    owner = "rokoucha";
    repo = "networkd-prefix-watcher";
    rev = version;
    hash = "sha256-l9ZacEttm0J9qkrAYNs0GC9J+vH4iKmyGRe5+TSWFtY=";
  };

  vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";
}
