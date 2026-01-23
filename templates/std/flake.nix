{
  description = "Standard template with full nixos-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
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
    };
}
