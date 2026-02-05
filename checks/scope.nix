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

  # Create a temporary source tree with scope.nix and package.nix
  scopedSource = pkgs.runCommand "scoped-source" { } ''
    mkdir -p $out/pkgs/scoped
    # Define scope: injects myScopedValue
    echo '{ pkgs, ... }: { scope = pkgs.lib.makeScope pkgs.newScope (self: {}); args = { myScopedValue = "dynamic-value"; }; }' > $out/pkgs/scoped/scope.nix
    # Define package consuming scope
    echo '{ pkgs, myScopedValue, ... }: pkgs.runCommand "scoped-pkg" {} "echo ''${myScopedValue} > $out"' > $out/pkgs/scoped/package.nix
  '';

  # Scope test using the dynamic source
  testFlakeScope =
    flake-fhs.mkFlake
      {
        self = {
          outPath = scopedSource;
        };
        inputs = {
          inherit self;
          nixpkgs = {
            outPath = pkgs.path;
            lib = pkgs.lib;
          };
        };
      }
      {
        # Override the root layout to point to our dynamic source
        layout = {
          roots = {
            subdirs = [ "" ];
          };
        };
      };
in
pkgs.runCommand "check-scope" { } ''
  echo "Checking testFlakeScope output..."
  if [ -z "${testFlakeScope.packages.${pkgs.stdenv.hostPlatform.system}.scoped}" ]; then
    echo "FAILED: packages.scoped missing in scoped flake"
    exit 1
  fi

  SCOPED_OUT=$(cat ${testFlakeScope.packages.${pkgs.stdenv.hostPlatform.system}.scoped})
  if [ "$SCOPED_OUT" != "dynamic-value" ]; then
    echo "FAILED: packages.scoped content mismatch. Expected 'dynamic-value', got '$SCOPED_OUT'"
    exit 1
  fi

  echo "PASS" > $out
''
