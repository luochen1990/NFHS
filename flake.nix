{
  description = "Flake FHS - Filesystem Hierarchy Standard for Nix flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let
      inherit (import ./utils) mkFlake;
    in
    (mkFlake {
      root = [ ./. ];
      inherit (inputs) self;
      lib = nixpkgs.lib;
      nixpkgs = nixpkgs;
      inherit inputs;
    }) // {
      # Export mkFlake function for external use
      inherit mkFlake;
    };
}
