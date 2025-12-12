{
  description = "Simple project using Flake FHS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-fhs,
      ...
    }:
    flake-fhs.lib.mkFlake {
      inherit self nixpkgs;
      lib = nixpkgs.lib;
      root = [ ./. ];
      nixpkgsConfig = {
        allowUnfree = true;
      };
    };
}
