# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS configuration schemas
#
lib:
let
  inherit (import ./file.nix) trimPath;

  # trimPathList : [String] -> [String]
  # Apply trimPath to each element in the list
  trimPathList = paths: map trimPath paths;

  # ================================================================
  # Configuration Schema
  # ================================================================

  # Configuration Module Schema
  flakeFhsOptions =
    { lib, ... }:
    {
      options = {
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = lib.systems.flakeExposed;
          description = "List of supported systems";
        };

        nixpkgs.config = lib.mkOption {
          type = lib.types.attrs;
          default = {
            allowUnfree = true;
          };
          description = "Nixpkgs configuration";
        };

        nixpkgs.overlays = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "Nixpkgs overlays";
        };

        layout = lib.mkOption {
          type = lib.types.submodule {
            options = {
              roots = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  ""
                ];
                apply = trimPathList;
                description = "Roots directories";
              };

              packages.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "pkgs"
                  "packages"
                ];
                apply = trimPathList;
                description = "Packages directories";
              };

              nixosModules = {
                subdirs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "modules"
                    "nixosModules"
                  ];
                  apply = trimPathList;
                  description = "NixOS modules directories";
                };

                guardedSuffix = lib.mkOption {
                  type = lib.types.str;
                  default = ".cfg.nix";
                  description = ''
                    File suffix for guarded config files. Files matching this suffix
                    are automatically collected within a directory module's scope and
                    wrapped with `mkIf (enable-chain)`. The enable-chain is the AND of
                    all ancestor module enables and the module's own enable.
                  '';
                  example = ".guarded.nix";
                };

                strictOptions = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    Validate that options declared in module files are namespaced
                    under their module path (e.g. modules/foo/default.nix must
                    define options under `foo.*`).
                    Violations are reported via config.assertions.
                  '';
                };
              };

              nixosConfigurations.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "hosts"
                  "nixosConfigurations"
                ];
                apply = trimPathList;
                description = "NixOS configurations directories";
              };

              devShells.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "shells"
                  "devShells"
                ];
                apply = trimPathList;
                description = "DevShells directories";
              };

              apps.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "apps" ];
                apply = trimPathList;
                description = "Apps directories";
              };

              lib.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "lib"
                ];
                apply = trimPathList;
                description = "Lib directories";
              };

              checks.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "checks" ];
                apply = trimPathList;
                description = "Checks directories";
              };

              templates.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "templates" ];
                apply = trimPathList;
                description = "Templates directories";
              };
            };
          };
          default = { };
          description = "Directory layout configuration";
        };

        colmena = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "colmena integration";
            };
          };
          default = { };
          description = "Colmena configuration";
        };

        flake = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Extra flake outputs to merge with FHS outputs";
        };

        evalContext = lib.mkOption {
          description = "Context generator for evaluation environments (e.g., specific architecture or host)";
          default = _: { };
          type = lib.mkOptionType {
            name = "evalContext";
            description = "function ({ system, pkgs, config, overlays }) -> attrs";
            check = lib.isFunction;
            merge =
              loc: defs: ctx:
              lib.foldl' (acc: def: lib.recursiveUpdate acc (def.value ctx)) { } defs;
          };
        };
      };
    };
in
{
  inherit flakeFhsOptions;
}
