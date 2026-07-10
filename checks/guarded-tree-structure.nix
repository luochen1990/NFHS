# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: GuardedTree structure and guardedPaths semantics
# - Verifies that guardedPaths only contains directories with options.nix
# - Verifies root directory with options.nix throws an error
# - Verifies intermediate directories without options.nix are not collected
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create test directory structure:
  # modules/
  # ├── a/
  # │   ├── options.nix        <- guarded module
  # │   ├── config.nix
  # │   └── b/
  # │       └── c/
  # │           ├── options.nix    <- guarded module (nested under a)
  # │           └── config.nix
  # └── d/
  #     └── e/
  #         └── options.nix    <- guarded module (no parent guarded)
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/a/b/c
    mkdir -p $out/modules/d/e

    # a/b/options.nix - guarded module at level 2
    cat > $out/modules/a/options.nix << 'EOF'
    { lib, ... }:
    {
      options.a = lib.mkOption {
        type = lib.types.str;
        default = "a-default";
      };
    }
    EOF

    cat > $out/modules/a/config.nix << 'EOF'
    { lib, ... }:
    {
      config.a = "a-configured";
    }
    EOF

    # a/b/c/options.nix - guarded module at level 4 (nested under a)
    cat > $out/modules/a/b/c/options.nix << 'EOF'
    { lib, ... }:
    {
      options.a.b.c = lib.mkOption {
        type = lib.types.str;
        default = "abc-default";
      };
    }
    EOF

    cat > $out/modules/a/b/c/config.nix << 'EOF'
    { lib, ... }:
    {
      config.a.b.c = "abc-configured";
    }
    EOF

    # d/e/options.nix - guarded module at level 3 (no parent guarded)
    cat > $out/modules/d/e/options.nix << 'EOF'
    { lib, ... }:
    {
      options.d.e = lib.mkOption {
        type = lib.types.str;
        default = "de-default";
      };
    }
    EOF
  '';

  # Build guarded tree
  guardedTree = fhs-modules.mkGuardedTree (testSource + "/modules") ".nix";

  # Helper to collect all nodes recursively
  collectAllNodes = tree: [ tree ] ++ lib.concatLists (map collectAllNodes tree.guardedChildren);

  allNodes = collectAllNodes guardedTree;

  # Count nodes with non-empty modPath (actual guarded modules)
  guardedModuleCount = lib.length (lib.filter (t: t.modPath != [ ]) allNodes);

  # Expected: 3 guarded modules (a, a.b.c, d.e)
  expectedModuleCount = 3;

  # Extract modPaths for verification
  guardedModPaths = map (t: lib.concatStringsSep "." t.modPath) (
    lib.filter (t: t.modPath != [ ]) allNodes
  );

  # Verify each guarded module has options.nix
  allGuardedHaveOptions = lib.all (t: builtins.pathExists (t.path + "/options.nix")) (
    lib.filter (t: t.modPath != [ ]) allNodes
  );

  # Test: Root directory with options.nix should throw error
  testRootWithOptions = pkgs.runCommand "test-root-options" { } ''
    mkdir -p $out/modules
    cat > $out/modules/options.nix << 'EOF'
    { lib, ... }:
    {
      options.root = lib.mkEnableOption "root";
    }
    EOF
  '';

  # This should throw an error
  rootOptionsError =
    let
      result = builtins.tryEval (fhs-modules.mkGuardedTree (testRootWithOptions + "/modules") ".nix");
    in
    if result.success then
      "FAIL: Should have thrown error for root options.nix"
    else
      # When assertion fails, result.value contains the error
      # We just need to verify it failed, the exact message format varies
      "PASS: Root options.nix correctly throws error";

  # Test checks
  checks = {
    # Test 1: Verify we have exactly 3 guarded modules
    testModuleCount =
      if guardedModuleCount != expectedModuleCount then
        "FAIL: Expected ${toString expectedModuleCount} guarded modules, got ${toString guardedModuleCount}"
      else
        "PASS: Found ${toString expectedModuleCount} guarded modules";

    # Test 2: Verify the correct modules are collected
    testCorrectModules =
      let
        expected = [
          "a"
          "a.b.c"
          "d.e"
        ];
        sortedGot = lib.sort (a: b: a < b) guardedModPaths;
        sortedExpected = lib.sort (a: b: a < b) expected;
      in
      if sortedGot != sortedExpected then
        "FAIL: Expected modules ${lib.concatStringsSep ", " sortedExpected}, got ${lib.concatStringsSep ", " sortedGot}"
      else
        "PASS: Correct modules collected: ${lib.concatStringsSep ", " sortedGot}";

    # Test 3: Verify all guarded modules have options.nix
    testAllHaveOptions =
      if !allGuardedHaveOptions then
        "FAIL: Some guarded modules don't have options.nix"
      else
        "PASS: All guarded modules have options.nix";

    # Test 4: Verify root directory with options.nix throws error
    testRootOptionsError = rootOptionsError;

    # Test 5: Verify intermediate directories (a/b) are NOT collected
    testIntermediateNotCollected =
      let
        hasAB = lib.elem "a.b" guardedModPaths;
      in
      if hasAB then
        "FAIL: Intermediate directory 'a/b' (without options.nix) should NOT be collected"
      else
        "PASS: Intermediate directories correctly excluded";
  };

in
pkgs.runCommand "check-guarded-tree-structure" { } ''
  echo "=== Test 1: Verify guarded module count ==="
  echo "${checks.testModuleCount}"

  echo ""
  echo "=== Test 2: Verify correct modules collected ==="
  echo "${checks.testCorrectModules}"

  echo ""
  echo "=== Test 3: Verify all guarded modules have options.nix ==="
  echo "${checks.testAllHaveOptions}"

  echo ""
  echo "=== Test 4: Verify root options.nix throws error ==="
  echo "${checks.testRootOptionsError}"

  echo ""
  echo "=== Test 5: Verify intermediate directories excluded ==="
  echo "${checks.testIntermediateNotCollected}"

  echo ""
  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
