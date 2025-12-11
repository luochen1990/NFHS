{
  description = "Flake FHS - Filesystem Hierarchy Standard for Nix flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let
      # Import utils which includes mkFlake function
      utils = import ./utils;
      lib = nixpkgs.lib;
    in
    rec {
      # Main mkFlake function - available as both a flake output and for direct use
      inherit (utils) mkFlake;

      # Templates are manually defined for now
      templates.simple-project = {
        path = ./templates/simple-project;
        description = "Simple project template with packages, shells, apps, and lib";
      };

      templates.package-module = {
        path = ./templates/package-module;
        description = "NixOS module development template";
      };

      templates.full-featured = {
        path = ./templates/full-featured;
        description = "Full-featured project template with all components";
      };

      templates.default = templates.simple-project;

      # Formatter for this project
      formatter = builtins.mapAttrs (system: pkgs:
        pkgs.nixfmt-tree or pkgs.nixfmt
      ) nixpkgs.legacyPackages;
    };
}