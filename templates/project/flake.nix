{
  description = "Project-embedded template with ./nix directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs =
    inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      layout.roots = [ "/nix" ];
      # systems = [
      #   "x86_64-linux"
      #   "x86_64-darwin"
      #   "aarch64-linux"
      # ];
      # nixpkgs.config = {
      #   allowUnfree = true;
      # };
    };
}
