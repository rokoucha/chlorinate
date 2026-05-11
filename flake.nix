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
      mape = (pkgs.buildGoModule.override { go = pkgs.go_1_26; }) {
        pname = "mape";
        version = "0.1.0";
        src = ./mape;
        vendorHash = "sha256-hdtuCCbnl2BpVm+JgREGp5dPM/RctypjurtoNidx5s0=";
      };
    in
    {
      packages.${system}.mape = mape;

      checks.${system}.mape = mape;

      nixosConfigurations.chlorinate = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          lanzaboote.nixosModules.lanzaboote
          ./nixos/hosts/chlorinate/configuration.nix
          { nixpkgs.pkgs = pkgs; }
        ];
        specialArgs = { inherit mape; };
      };
    };
}
