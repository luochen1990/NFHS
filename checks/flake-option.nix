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

  # 1. Minimal test
  testFlake =
    flake-fhs.mkFlake
      {
        inherit self;
        inputs = {
          inherit self;
          nixpkgs = {
            outPath = pkgs.path;
            lib = pkgs.lib;
          };
        };
      }
      {
        layout = {
          roots = {
            subdirs = [ ];
          };
        };
        flake = {
          testOutput = "success";
          packages.${pkgs.stdenv.hostPlatform.system}.hello = pkgs.hello;
        };
      };

  # 2. Collision/Override test
  dummySource = pkgs.runCommand "dummy-source" { } ''
    mkdir -p $out/pkgs/foo
    # Define a package that produces "fhs"
    echo '{ pkgs, ... }: pkgs.runCommand "foo-fhs" {} "echo fhs > $out"' > $out/pkgs/foo/package.nix
  '';

  testFlakeCollision =
    flake-fhs.mkFlake
      {
        self = {
          outPath = dummySource;
          inputs = { };
        };
        inputs = {
          self = {
            outPath = dummySource;
            inputs = { };
          };
          nixpkgs = {
            outPath = pkgs.path;
            lib = pkgs.lib;
          };
        };
      }
      {
        # Use defaults which include "pkgs" directory
        flake = {
          # Override foo and add bar
          packages.${pkgs.stdenv.hostPlatform.system} = {
            foo = pkgs.runCommand "foo-manual" { } "echo manual > $out";
            bar = pkgs.hello;
          };
        };
      };
in
pkgs.runCommand "check-flake-option" { } ''
  echo "Checking testFlake output..."
  if [ "${testFlake.testOutput}" != "success" ]; then
    echo "FAILED: testFlake.testOutput should be 'success', got '${toString testFlake.testOutput}'"
    exit 1
  fi

  if [ -z "${testFlake.packages.${pkgs.stdenv.hostPlatform.system}.hello}" ]; then
    echo "FAILED: testFlake.packages.hello missing"
    exit 1
  fi

  echo "Checking testFlakeCollision output..."
  # Check override
  FOO_OUT=$(cat ${testFlakeCollision.packages.${pkgs.stdenv.hostPlatform.system}.foo})
  if [ "$FOO_OUT" != "manual" ]; then
    echo "FAILED: packages.foo should be overridden to 'manual', got '$FOO_OUT'"
    exit 1
  fi

  # Check merge (bar exists)
  if [ -z "${testFlakeCollision.packages.${pkgs.stdenv.hostPlatform.system}.bar}" ]; then
    echo "FAILED: packages.bar missing in collision flake"
    exit 1
  fi

  echo "PASS" > $out
''
