{
  description = "自家製ルーター";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, lanzaboote, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mapeTool = pkgs.callPackage ./pkgs/mape-tool.nix { };
      networkdPrefixWatcher = pkgs.callPackage ./pkgs/networkd-prefix-watcher.nix { };
      cloudflareDdns = pkgs.callPackage ./pkgs/cloudflare-ddns.nix { };
      ciliumLbIpv6PoolUpdater = pkgs.callPackage ./pkgs/cilium-lb-ipv6-pool-updater.nix { };
      otelcol = pkgs.callPackage ./pkgs/otelcol.nix { };
    in
    {
      packages.${system} = {
        mape-tool = mapeTool;
        networkd-prefix-watcher = networkdPrefixWatcher;
        cloudflare-ddns = cloudflareDdns;
        cilium-lb-ipv6-pool-updater = ciliumLbIpv6PoolUpdater;
        inherit otelcol;
      };

      nixosConfigurations.chlorine = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          lanzaboote.nixosModules.lanzaboote
          ./nixos/hosts/chlorine/configuration.nix
          { nixpkgs.pkgs = pkgs; }
        ];
        specialArgs = {
          inherit
            mapeTool
            networkdPrefixWatcher
            cloudflareDdns
            ciliumLbIpv6PoolUpdater
            otelcol
            ;
        };
      };
    };
}
