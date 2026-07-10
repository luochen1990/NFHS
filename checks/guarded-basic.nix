# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Basic guarded module functionality
# - Verifies enable option auto-generation
# - Verifies config is wrapped with mkIf
# - Verifies module is exported correctly
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create test directory structure
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/myapp
    # options.nix with option definitions following module path
    cat > $out/modules/myapp/options.nix << 'EOF'
    { lib, ... }:
    {
      options.myapp = {
        message = lib.mkOption {
          type = lib.types.str;
          default = "hello";
        };
        status = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };
    }
    EOF
    # config.nix
    cat > $out/modules/myapp/config.nix << 'EOF'
    { config, lib, ... }:
    {
      config.myapp.status = "config-applied";
    }
    EOF
  '';

  # Build guarded tree
  guardedTree = fhs-modules.mkGuardedTree (testSource + "/modules") ".nix";

  # Collect modules
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".nix";
  firstInfo = builtins.head moduleInfos;

  # Wrap the module
  wrappedModule = fhs-modules.wrapModule guardedTree firstInfo;

  # Evaluate the module to verify structure
  evalResult = lib.evalModules {
    modules = [
      wrappedModule
      {
        config.myapp.enable = true;
      }
    ];
  };

  # Test checks (computed at eval time)
  checks = {
    # Test 1: Check guarded tree has correct modPath
    testTreeModPath =
      let
        child = builtins.head guardedTree.guardedChildren;
      in
      if builtins.concatStringsSep "." child.modPath != "myapp" then
        "FAIL: Expected modPath 'myapp', got '${builtins.concatStringsSep "." child.modPath}'"
      else
        "PASS: Guarded tree has correct modPath";

    # Test 2: Check module info collection
    testModuleCount =
      if builtins.length moduleInfos != 1 then
        "FAIL: Expected 1 module info, got ${toString (builtins.length moduleInfos)}"
      else
        "PASS: Module info collected correctly";

    testModuleType =
      if firstInfo.moduleType != "guarded" then
        "FAIL: Expected moduleType 'guarded', got '${firstInfo.moduleType}'"
      else
        "PASS: Module type is guarded";

    # Test 3: Check enable option exists
    testEnableExists =
      if !(builtins.hasAttr "enable" evalResult.options.myapp) then
        "FAIL: Enable option not found in myapp options. Available: ${builtins.concatStringsSep ", " (builtins.attrNames evalResult.options.myapp)}"
      else
        "PASS: Enable option exists";

    # Test 4: Check config evaluates correctly when enabled
    testConfigResult =
      if evalResult.config.myapp.status != "config-applied" then
        "FAIL: Expected myapp.status = 'config-applied', got '${toString evalResult.config.myapp.status}'"
      else
        "PASS: Config evaluates correctly";

    # Test 5: Check config is NOT applied when disabled
    testDisabledConfig =
      let
        evalDisabled = lib.evalModules {
          modules = [
            wrappedModule
            {
              config.myapp.enable = false;
            }
          ];
        };
      in
      if evalDisabled.config.myapp.status != "" then
        "FAIL: Config should NOT be applied when disabled, but got status = '${toString evalDisabled.config.myapp.status}'"
      else
        "PASS: Config correctly guarded";
  };

in
pkgs.runCommand "check-guarded-basic" { } ''
  echo "=== Test 1: Check guarded tree modPath ==="
  echo "${checks.testTreeModPath}"

  echo ""
  echo "=== Test 2: Check module info collection ==="
  echo "${checks.testModuleCount}"
  echo "${checks.testModuleType}"

  echo ""
  echo "=== Test 3: Check enable option exists ==="
  echo "${checks.testEnableExists}"

  echo ""
  echo "=== Test 4: Check config evaluates correctly when enabled ==="
  echo "${checks.testConfigResult}"

  echo ""
  echo "=== Test 5: Check config is NOT applied when disabled ==="
  echo "${checks.testDisabledConfig}"

  echo ""
  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
