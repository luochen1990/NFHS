# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Single file module functionality
# - Verifies standalone .nix files are recognized as modules
# - Verifies no enable mechanism for single file modules
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
  # Create test directory structure with single file modules:
  # modules/
  # ├── utils.nix
  # └── helpers/
  #     └── common.nix
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/helpers

    # Single file module at root level
    cat > $out/modules/utils.nix << 'EOF'
    { lib, ... }:
    {
      options.utils.feature = lib.mkEnableOption "utils feature";
      config.utils.feature = true;
    }
    EOF

    # Single file module in subdirectory
    cat > $out/modules/helpers/common.nix << 'EOF'
    { lib, ... }:
    {
      options.helpers.common.setting = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      config.helpers.common.setting = true;
    }
    EOF
  '';

  # Build guarded tree
  guardedTree = fhs-modules.mkGuardedTree (testSource + "/modules") ".nix";

  # Collect modules
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".nix";

  # Find single file modules
  utilsInfo = lib.findFirst (
    m: m.moduleType == "single" && m.modPath == [ "utils" ]
  ) null moduleInfos;
  commonInfo = lib.findFirst (
    m:
    m.moduleType == "single"
    &&
      m.modPath == [
        "helpers"
        "common"
      ]
  ) null moduleInfos;

  # Count single file modules
  singleFileCount = lib.length (lib.filter (m: m.moduleType == "single") moduleInfos);

  # Wrap modules
  utilsModule = fhs-modules.wrapModule guardedTree utilsInfo;
  commonModule = fhs-modules.wrapModule guardedTree commonInfo;

  # Evaluate utils module
  utilsEval = lib.evalModules {
    modules = [ utilsModule ];
  };

  # Evaluate common module
  commonEval = lib.evalModules {
    modules = [ commonModule ];
  };

  # Test checks
  checks = {
    # Test 1: Verify we found 2 single file modules
    testCount =
      if singleFileCount != 2 then
        "FAIL: Expected 2 single file modules, got ${toString singleFileCount}"
      else
        "PASS: Found 2 single file modules";

    # Test 2: Verify utils module type and path
    testUtilsInfo =
      if utilsInfo.moduleType != "single" then
        "FAIL: Expected utils moduleType 'single', got '${utilsInfo.moduleType}'"
      else if utilsInfo.kind != "file" then
        "FAIL: Expected utils kind 'file', got '${utilsInfo.kind}'"
      else
        "PASS: utils module is single file type";

    # Test 3: Verify helpers.common module type and path
    testCommonInfo =
      if commonInfo.moduleType != "single" then
        "FAIL: Expected common moduleType 'single', got '${commonInfo.moduleType}'"
      else if builtins.concatStringsSep "." commonInfo.modPath != "helpers.common" then
        "FAIL: Expected common modPath 'helpers.common', got '${builtins.concatStringsSep "." commonInfo.modPath}'"
      else
        "PASS: helpers.common module is single file type";

    # Test 4: Verify utils config is always applied
    testUtilsConfig =
      if utilsEval.config.utils.feature != true then
        "FAIL: Single file module config should always be applied"
      else
        "PASS: utils config applied";

    # Test 5: Verify common config is always applied
    testCommonConfig =
      if commonEval.config.helpers.common.setting != true then
        "FAIL: Single file module config in subdirectory should always be applied"
      else
        "PASS: common config applied";

    # Test 6: Verify no auto-generated enable for single file modules
    testNoAutoEnable =
      if builtins.hasAttr "enable" utilsEval.options.utils then
        "FAIL: Single file module should NOT have auto-generated enable option"
      else
        "PASS: No auto-generated enable option";
  };

in
pkgs.runCommand "check-single-file" { } ''
  echo "=== Test 1: Verify single file module count ==="
  echo "${checks.testCount}"

  echo ""
  echo "=== Test 2: Verify utils module type and path ==="
  echo "${checks.testUtilsInfo}"

  echo ""
  echo "=== Test 3: Verify helpers.common module type and path ==="
  echo "${checks.testCommonInfo}"

  echo ""
  echo "=== Test 4: Verify utils config is always applied ==="
  echo "${checks.testUtilsConfig}"

  echo ""
  echo "=== Test 5: Verify common config is always applied ==="
  echo "${checks.testCommonConfig}"

  echo ""
  echo "=== Test 6: Verify no auto-generated enable ==="
  echo "${checks.testNoAutoEnable}"

  echo ""
  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
