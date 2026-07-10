{
  description = "Reference: template with long directory names and colmena";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
    flake-fhs.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      layout.roots = [ "" ];
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
      ];
      nixpkgs.config = {
        allowUnfree = true;
      };
      colmena.enable = true;
    };
}
