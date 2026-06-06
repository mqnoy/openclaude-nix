{
  description = "Nix flake for OpenClaude CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          openclaude = pkgs.callPackage ./openclaude.nix {};
          default = self.packages.${system}.openclaude;
        };

        apps = {
          openclaude = flake-utils.lib.mkApp {
            drv = self.packages.${system}.openclaude;
          };
          default = self.apps.${system}.openclaude;
        };
      }
    ) // {
      # Module for easy NixOS / Home Manager consumption
      homeManagerModules.default = { pkgs, config, lib, ... }: {
        home.packages = [ self.packages.${pkgs.system}.default ];
      };
      
      nixosModules.default = { pkgs, config, lib, ... }: {
        environment.systemPackages = [ self.packages.${pkgs.system}.default ];
      };
    };
}
