{
  pkgs,
  lib,
  self,
  ...
}:

let
  # Replicate library setup
  utils' = lib // (import ../lib/list.nix) // (import ../lib/dict.nix) // (import ../lib/file.nix);
  inherit (import ../lib/prepare-lib.nix utils') prepareLib;

  libWithUtils = utils' // {
    inherit prepareLib;
  };

  # Import the core library
  flake-fhs = import ../lib/flake-fhs.nix libWithUtils;

  # Create mock source tree
  mockRoot = pkgs.runCommand "mock-source" { } ''
    mkdir -p $out/modules/auto/nested
    echo '{ lib, ... }: { options.bar = lib.mkOption { type = lib.types.str; default = "auto-val"; }; }' > $out/modules/auto/nested/options.nix

    mkdir -p $out/modules/strict/nested
    echo '{ lib, ... }: { options.nested.bar = lib.mkOption { type = lib.types.str; default = "strict-val"; }; }' > $out/modules/strict/nested/options.nix

    mkdir -p $out/modules/free/nested
    echo '{ lib, ... }: { options.anywhere.other = lib.mkOption { type = lib.types.str; default = "free-val"; }; }' > $out/modules/free/nested/options.nix
  '';

  # Helper to make flake
  mkFlake =
    mode: subdir:
    flake-fhs.mkFlake
      {
        self = {
          outPath = mockRoot;
          inputs = { };
        };
        inputs = {
          self = {
            outPath = mockRoot;
            inputs = { };
          };
          nixpkgs = {
            outPath = pkgs.path;
            lib = pkgs.lib;
          };
        };
      }
      (
        {
          layout = {
            nixosModules.subdirs = [ "modules/${subdir}" ];
          };
        }
        // (if mode == null then { } else { optionsMode = mode; })
      );

  flakeAuto = mkFlake "auto" "auto";
  flakeStrict = mkFlake "strict" "strict";
  flakeFree = mkFlake "free" "free";
  flakeDefault = mkFlake null "strict"; # Default should be strict

  evalSys =
    flake:
    lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        flake.nixosModules.default
      ]
      ++ (lib.attrValues (removeAttrs flake.nixosModules [ "default" ]));
    };

  sysAuto = evalSys flakeAuto;
  sysStrict = evalSys flakeStrict;
  sysFree = evalSys flakeFree;
  sysDefault = evalSys flakeDefault;
in
pkgs.runCommand "check-options-mode"
  {
    autoBar = sysAuto.config.nested.bar or "MISSING_NESTED";
    autoBarTop = sysAuto.config.bar or "MISSING_TOP";
    strictBar = sysStrict.config.nested.bar or "MISSING";
    freeBar = sysFree.config.anywhere.other or "MISSING";
    defaultBar = sysDefault.config.nested.bar or "MISSING";
  }
  ''
    echo "Auto Nested: $autoBar"
    echo "Auto Top: $autoBarTop"

    if [ "$autoBar" != "auto-val" ]; then
      echo "FAILED: Auto mode: expected 'auto-val', got '$autoBar'"
      exit 1
    fi

    if [ "$strictBar" != "strict-val" ]; then
      echo "FAILED: Strict mode: expected 'strict-val', got '$strictBar'"
      exit 1
    fi

    if [ "$freeBar" != "free-val" ]; then
      echo "FAILED: Free mode: expected 'free-val', got '$freeBar'"
      exit 1
    fi

    if [ "$defaultBar" != "strict-val" ]; then
      echo "FAILED: Default mode (strict): expected 'strict-val', got '$defaultBar'"
      exit 1
    fi

    echo "PASS" > $out
  ''
