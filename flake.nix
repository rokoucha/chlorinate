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
      # renovate: datasource=github-release-attachments depName=rokoucha/mape-tool versioning=regex:^(?<major>\d{8})\.(?<minor>\d{6})$
      mapeToolVersion = "20260527.230833";
      mapeToolHash = "195217920b900e82475200077e8918b5e5228dffb294120e91bff6e62c8235ea";
      mapeTool = pkgs.stdenvNoCC.mkDerivation {
        pname = "mape-tool";
        version = mapeToolVersion;

        src = pkgs.fetchurl {
          url = "https://github.com/rokoucha/mape-tool/releases/download/${mapeToolVersion}/mape-tool-linux-amd64";
          hash = "sha256:${mapeToolHash}";
        };

        dontUnpack = true;

        installPhase = ''
          install -Dm755 "$src" "$out/bin/mape-tool"
        '';
      };
    in
    {
      packages.${system} = {
        mape-tool = mapeTool;
        mape = mapeTool;
      };

      checks.${system} = {
        mape-tool = mapeTool;
        mape = mapeTool;
      };

      nixosConfigurations.chlorinate = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          lanzaboote.nixosModules.lanzaboote
          ./nixos/hosts/chlorinate/configuration.nix
          { nixpkgs.pkgs = pkgs; }
        ];
        specialArgs = { inherit mapeTool; };
      };
    };
}
