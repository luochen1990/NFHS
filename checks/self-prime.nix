# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: self' (system-resolved raw scan view) exposed in evalContext.
#
# Verifies:
#   - self'.packages / apps / checks contain raw derivations from the pkgs/apps/checks dirs
#   - self' is usable inside devShells without infinite recursion (the core guarantee)
#   - devShells can consume self' via inputsFrom / packages
#
{
  pkgs,
  lib,
  self,
  flake-fhs,
  mkCheck,
  ...
}:

let
  # assertOk :: Bool -> String -> String
  # Unified PASS/FAIL string — drops the repeated `if … then "PASS" else "FAIL: …"` boilerplate.
  assertOk = cond: failMsg: if cond then "PASS" else "FAIL: ${failMsg}";

  # ----------------------------------------------------------------
  # Test fixture: tiny flake with pkgs/foo, apps/bar, checks/baz, shells/uses-self-prime.
  # Files are written via pkgs.writeText (not heredoc) to avoid embedding Nix's ''
  # terminator inside another '' string.
  # ----------------------------------------------------------------
  fooPkgNix = pkgs.writeText "foo-package.nix" ''
    { pkgs, ... }:
    pkgs.runCommand "fhs-test-foo" { } "echo foo-out > $out"
  '';

  barPkgNix = pkgs.writeText "bar-package.nix" ''
    { pkgs, ... }:
    pkgs.runCommand "fhs-test-bar"
      { meta.mainProgram = "bar"; }
      "mkdir -p $out/bin; echo '#!/bin/sh' > $out/bin/bar; chmod +x $out/bin/bar"
  '';

  bazCheckNix = pkgs.writeText "baz-check.nix" ''
    { pkgs, ... }:
    pkgs.runCommand "fhs-test-baz" { } "echo baz-out > $out"
  '';

  # devShell that consumes self' — the core use case under test.
  # If self' caused infinite recursion, evaluating this shell would deadlock.
  usesSelfPrimeShellNix = pkgs.writeText "uses-self-prime.nix" ''
    { pkgs, self', ... }:
    pkgs.mkShell {
      packages = [ self'.packages.foo ];
      inputsFrom = [ self'.apps.bar ];
    }
  '';

  testSource = pkgs.runCommand "self-prime-test-source" { } ''
    mkdir -p $out/pkgs/foo $out/apps/bar $out/checks/baz $out/shells
    cp ${fooPkgNix}             $out/pkgs/foo/package.nix
    cp ${barPkgNix}             $out/apps/bar/package.nix
    cp ${bazCheckNix}           $out/checks/baz/package.nix
    cp ${usesSelfPrimeShellNix} $out/shells/uses-self-prime.nix
  '';

  # Instantiate the flake with a mocked self pointing at testSource.
  testFlake =
    flake-fhs.mkFlake
      {
        self = { outPath = testSource; };
        inputs = {
          inherit self;
          nixpkgs = {
            outPath = pkgs.path;
            lib = pkgs.lib;
          };
        };
      }
      { };

  system = pkgs.stdenv.hostPlatform.system;

  # self' lives in evalContext (visible to user code like shells/*.nix), not on the
  # final flake outputs. The fact that `shellFinal` evaluates successfully already
  # proves self' resolved foo/bar without infinite recursion — the shell's body
  # references `self'.packages.foo` and `self'.apps.bar`.
  appBarFinal = testFlake.apps.${system}.bar;
  shellFinal = testFlake.devShells.${system}.uses-self-prime;

  checks = {
    # Sanity: outputs are present.
    testPackagesPresent = assertOk (builtins.hasAttr "foo" testFlake.packages.${system}) "packages.foo missing";
    testAppsPresent = assertOk (builtins.hasAttr "bar" testFlake.apps.${system}) "apps.bar missing";
    testChecksPresent = assertOk (builtins.hasAttr "baz" testFlake.checks.${system}) "checks.baz missing";

    # app structure is built from the raw drv (program path ends with /bin/bar).
    testAppProgramPath =
      assertOk (lib.hasSuffix "/bin/bar" appBarFinal.program)
        "app program should end with /bin/bar, got '${appBarFinal.program}'";

    # Core guarantee: devShell that consumes self' evaluates without deadlock.
    # If self' recursed, forcing shellFinal would throw instead of reaching here.
    testShellEvaluatesWithoutDeadlock =
      assertOk (builtins.isAttrs shellFinal) "devShell.uses-self-prime did not evaluate to an attrset";

    # The shell is a real derivation (has outPath).
    testShellIsDerivation =
      assertOk (builtins.isString shellFinal.outPath) "devShell.uses-self-prime.outPath is not a string";

    # Force evaluation of the foo drv via the final flake output. self'.packages.foo
    # and the final packages.${system}.foo come from the same loadScopedOutputs call,
    # so this transitively proves the raw scan (and thus self') resolved cleanly.
    testFooDrvNonEmpty =
      assertOk (builtins.stringLength testFlake.packages.${system}.foo.outPath > 0)
        "packages.foo.outPath is empty";
  };

in
mkCheck "self-prime" checks
