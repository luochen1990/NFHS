{
  description = "Flake FHS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      utils' =
        nixpkgs.lib // (import ./lib/list.nix) // (import ./lib/dict.nix) // (import ./lib/file.nix);
      inherit (import ./lib/prepare-lib.nix utils') prepareLib;
      inherit
        (prepareLib {
          roots = [ ./. ];
          lib = nixpkgs.lib;
        })
        mkFlake
        ;
    in
    mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
    };
}
