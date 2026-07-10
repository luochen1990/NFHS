# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Traditional directory module functionality
# - Verifies module is directly exported without enable mechanism
# - Verifies no options are auto-generated
# - Verifies config is always applied
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create test directory structure with traditional module:
  # modules/
  # └── configs/
  #     └── default.nix
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/configs

    # Traditional module with default.nix (no options.nix)
    cat > $out/modules/configs/default.nix << 'EOF'
    { lib, ... }:
    {
      options.configs.setting1 = lib.mkOption {
        type = lib.types.str;
        default = "default-value";
      };
      options.configs.setting2 = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      config.configs.setting2 = "always-set";
    }
    EOF
  '';

  # Build guarded tree
  guardedTree = fhs-modules.mkGuardedTree (testSource + "/modules") ".nix";

  # Collect modules
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".nix";

  # Find traditional module
  configsInfo = lib.findFirst (m: m.moduleType == "traditional") null moduleInfos;

  # Wrap module
  configsModule = fhs-modules.wrapModule guardedTree configsInfo;

  # Evaluate the module
  evalResult = lib.evalModules {
    modules = [ configsModule ];
  };

  # Test checks
  checks = {
    # Test 1: Verify module type
    testModuleType =
      if configsInfo.moduleType != "traditional" then
        "FAIL: Expected moduleType 'traditional', got '${configsInfo.moduleType}'"
      else
        "PASS: Module type is traditional";

    # Test 2: Verify modPath
    testModPath =
      if builtins.concatStringsSep "." configsInfo.modPath != "configs" then
        "FAIL: Expected modPath 'configs', got '${builtins.concatStringsSep "." configsInfo.modPath}'"
      else
        "PASS: modPath is correct";

    # Test 3: Verify config is always applied (no enable mechanism)
    testConfigAlwaysApplied =
      if evalResult.config.configs.setting2 != "always-set" then
        "FAIL: Traditional module config should always be applied"
      else
        "PASS: Config applied without enable mechanism";

    # Test 4: Verify no enable option is generated
    testNoEnableOption =
      if builtins.hasAttr "enable" evalResult.options.configs then
        "FAIL: Traditional module should NOT have auto-generated enable option"
      else
        "PASS: No auto-generated enable option";

    # Test 5: Verify user-defined options work
    testUserOptions =
      if evalResult.config.configs.setting1 != "default-value" then
        "FAIL: User-defined option should work"
      else
        "PASS: User-defined options work correctly";
  };

in
pkgs.runCommand "check-traditional-basic" { } ''
  echo "=== Test 1: Verify module type ==="
  echo "${checks.testModuleType}"

  echo ""
  echo "=== Test 2: Verify modPath ==="
  echo "${checks.testModPath}"

  echo ""
  echo "=== Test 3: Verify config is always applied ==="
  echo "${checks.testConfigAlwaysApplied}"

  echo ""
  echo "=== Test 4: Verify no enable option is generated ==="
  echo "${checks.testNoEnableOption}"

  echo ""
  echo "=== Test 5: Verify user-defined options work ==="
  echo "${checks.testUserOptions}"

  echo ""
  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
