# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Verify that layout.roots and layout.*.subdirs automatically apply trimPath
#
{
  pkgs,
  lib,
  self,
  flake-fhs,
  ...
}:

let
  # Create a test with paths that need trimming
  dummySource = pkgs.runCommand "dummy-source" { } ''
    mkdir -p $out/pkgs/foo
    echo '{ pkgs, ... }: pkgs.runCommand "foo" {} "echo foo > $out"' > $out/pkgs/foo/package.nix
  '';

  # Test with paths that have leading/trailing slashes
  testFlake =
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
        # These paths have slashes that should be automatically trimmed
        layout.roots = [ "/" ];
        layout.packages.subdirs = [ "pkgs/" ];
      };

  # Verify the configuration internally has trimmed values
  # We can't directly access the internal config, but we can verify behavior

in
pkgs.runCommand "check-trim-path-auto" { } ''
  echo "Testing automatic trimPath application..."

  # If trimPath works correctly, the package should be found
  # If it doesn't work, the build will fail because paths won't match
  if [ -z "${testFlake.packages.${pkgs.stdenv.hostPlatform.system}.foo}" ]; then
    echo "FAILED: Package not found - trimPath may not be working"
    exit 1
  fi

  # Verify the package builds correctly
  FOO_OUT=$(cat ${testFlake.packages.${pkgs.stdenv.hostPlatform.system}.foo})
  if [ "$FOO_OUT" != "foo" ]; then
    echo "FAILED: Package content incorrect"
    exit 1
  fi

  echo "SUCCESS: trimPath is automatically applied to layout options"
  touch $out
''
