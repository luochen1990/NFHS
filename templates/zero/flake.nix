{
  description = "Minimal template - only flake.nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs = inputs@{ flake-fhs, ... }: flake-fhs.lib.mkFlake { inherit inputs; } { };
}
