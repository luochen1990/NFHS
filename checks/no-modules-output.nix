# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: When no modules exist, nixosModules output should not contain default
#
# This test verifies that when a flake has no modules defined, the nixosModules
# output should not contain a 'default' attribute. This prevents unnecessary
# empty module imports.
#
{
  pkgs,
  lib,
  self,
  flake-fhs,
  ...
}:

let
  # Create mock source tree WITHOUT any modules
  mockRoot = pkgs.runCommand "mock-no-modules" { } ''
    # Create empty directory structure
    mkdir -p $out/empty
    mkdir -p $out/other

    # Add a non-module file
    echo '{ lib, ... }: { options.test = lib.mkOption { type = lib.types.str; }; }' > $out/other/file.nix
  '';

  # Create flake without modules
  testFlake =
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
      {
        layout = {
          nixosModules.subdirs = [ "modules" ]; # This directory doesn't exist
        };
      };

  # Extract check results
  hasDefault = builtins.hasAttr "default" (testFlake.nixosModules or { });
  moduleCount = builtins.length (builtins.attrNames (testFlake.nixosModules or { }));

  # Check results
  checks = {
    # Check 1: nixosModules should exist but be empty
    noModules =
      if moduleCount == 0 then "PASS" else "FAIL: Expected 0 modules, got ${toString moduleCount}";

    # Check 2: nixosModules should not have 'default' attribute
    noDefault =
      if !hasDefault then "PASS" else "FAIL: nixosModules should not have 'default' attribute";
  };

  checkResults = builtins.attrValues checks;

in
pkgs.runCommand "check-no-modules-output"
  {
    # Output actual check results (forces evaluation)
    inherit checkResults;
  }
  ''
    # Output actual check results
    ${builtins.concatStringsSep "\n" (map (r: "echo '${r}'") checkResults)}

    # Fail if any check failed
    if echo '${builtins.toJSON checks}' | grep -q FAIL; then
      exit 1
    fi

    echo "PASS: nixosModules correctly omitted when no modules exist"
    touch $out
  ''
