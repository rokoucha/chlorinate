{
  description = "自家製ルーター";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

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
      cloudflareDdns = pkgs.callPackage ./pkgs/cloudflare-ddns.nix { };
      otelcol = pkgs.callPackage ./pkgs/otelcol.nix { };
    in
    {
      packages.${system} = {
        mape-tool = mapeTool;
        cloudflare-ddns = cloudflareDdns;
        inherit otelcol;
      };

      nixosConfigurations.chlorine = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          lanzaboote.nixosModules.lanzaboote
          ./nixos/hosts/chlorine/configuration.nix
          { nixpkgs.pkgs = pkgs; }
        ];
        specialArgs = { inherit mapeTool cloudflareDdns otelcol; };
      };
    };
}
