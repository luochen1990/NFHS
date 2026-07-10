{
  description = "Recommended: minimal template for pure Nix projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
    flake-fhs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-fhs, ... }: flake-fhs.lib.mkFlake { inherit inputs; } { };
}
