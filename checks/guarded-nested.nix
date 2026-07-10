# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Nested guarded module functionality
# - Verifies nested modules check ALL parent enables
# - Verifies parentGuardedPaths is correctly propagated
# - Verifies nested mkIf conditions work correctly
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create nested test directory structure:
  # modules/
  # └── network/              # network.enable
  #     ├── options.nix
  #     ├── config.nix
  #     └── services/
  #         └── web/          # network.enable && network.services.web.enable
  #             ├── options.nix
  #             └── config.nix
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/network/services/web

    # Parent module: network
    # NOTE: We DON'T define 'enable' option - it will be auto-injected by wrapGuardedOptions
    cat > $out/modules/network/options.nix << 'EOF'
    { lib, ... }:
    {
      options.network = {
        status = lib.mkOption {
          type = lib.types.str;
          default = "not-applied";
        };
      };
    }
    EOF
    cat > $out/modules/network/config.nix << 'EOF'
    { config, ... }:
    {
      # This config will be automatically wrapped with mkIf config.network.enable
      # by the framework's wrapGuardedConfig function
      config.network.status = "parent-config-applied";
    }
    EOF

    # Child module: network/services/web
    # NOTE: We DON'T define 'enable' option - it will be auto-injected by wrapGuardedOptions
    cat > $out/modules/network/services/web/options.nix << 'EOF'
    { lib, ... }:
    {
      options.network.services.web = {
        port = lib.mkOption {
          type = lib.types.int;
          default = 80;
        };
        status = lib.mkOption {
          type = lib.types.str;
          default = "not-applied";
        };
      };
    }
    EOF
    cat > $out/modules/network/services/web/config.nix << 'EOF'
    { config, ... }:
    {
      # This config will be automatically wrapped with:
      # mkIf (config.network.enable && config.network.services.web.enable)
      # by the framework's wrapGuardedConfig function
      config.network.services.web.status = "child-config-applied";
    }
    EOF
  '';

  # Build guarded tree
  guardedTree = fhs-modules.mkGuardedTree (testSource + "/modules") ".nix";

  # Collect modules
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".nix";

  # Find parent and child module infos
  networkInfo = lib.findFirst (
    m: m.moduleType == "guarded" && m.modPath == [ "network" ]
  ) null moduleInfos;
  webInfo = lib.findFirst (
    m:
    m.moduleType == "guarded"
    &&
      m.modPath == [
        "network"
        "services"
        "web"
      ]
  ) null moduleInfos;

  # Wrap modules
  networkModule = fhs-modules.wrapModule guardedTree networkInfo;
  webModule = fhs-modules.wrapModule guardedTree webInfo;

  # Debug: Check if modules were found
  debugChecks = {
    moduleCount = builtins.length moduleInfos;
    networkInfoFound = networkInfo != null;
    webInfoFound = webInfo != null;
    networkInfoModPath = if networkInfo != null then networkInfo.modPath else null;
    webInfoModPath = if webInfo != null then webInfo.modPath else null;
    guardedTreeChildren = builtins.length guardedTree.guardedChildren;
    webInfoParentGuardedPaths = if webInfo != null then webInfo.parentGuardedPaths else null;
    # 新增：打印 guardedChildren 的 modPath
    childrenModPaths = map (c: c.modPath) guardedTree.guardedChildren;
  };

  # Test checks
  checks = {
    # Test 0: Verify modules were found
    testModulesFound =
      if !debugChecks.networkInfoFound then
        "FAIL: networkInfo is null! moduleInfos = ${builtins.toJSON (map (m: m.modPath) moduleInfos)}"
      else if !debugChecks.webInfoFound then
        "FAIL: webInfo is null! moduleInfos = ${builtins.toJSON (map (m: m.modPath) moduleInfos)}"
      else
        "PASS: Both modules found";

    # Test 1: Verify nested tree structure
    testNestedStructure =
      let
        networkChild = builtins.head guardedTree.guardedChildren;
        webGrandchild = builtins.head networkChild.guardedChildren;
      in
      if builtins.concatStringsSep "." networkChild.modPath != "network" then
        "FAIL: Expected parent modPath 'network', got '${builtins.concatStringsSep "." networkChild.modPath}'"
      else if builtins.concatStringsSep "." webGrandchild.modPath != "network.services.web" then
        "FAIL: Expected child modPath 'network.services.web', got '${builtins.concatStringsSep "." webGrandchild.modPath}'"
      else
        "PASS: Nested structure correct";

    # Test 2: Verify parentGuardedPaths for nested module
    testParentGuardedPaths =
      let
        networkChild = builtins.head guardedTree.guardedChildren;
        webGrandchild = builtins.head networkChild.guardedChildren;
      in
      # webGrandchild should have [ "network" ] as parentGuardedPaths
      if webGrandchild.parentGuardedPaths != [ [ "network" ] ] then
        "FAIL: Expected parentGuardedPaths [[ 'network' ]], got '${builtins.toJSON webGrandchild.parentGuardedPaths}'"
      else
        "PASS: parentGuardedPaths correctly propagated";

    # Test 2.5: Debug networkModule structure
    testNetworkModuleDebug =
      let
        # 检查 networkModule 的结构
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [ networkModule ];
            };
          in
          # 首先检查 eval 的基本结构
          if !builtins.hasAttr "options" eval then
            "FAIL: eval has no 'options' attr, keys: ${builtins.toJSON (builtins.attrNames eval)}"
          else
            let
              opts = eval.options;
            in
            # 检查 options 是否为空
            if opts == { } then
              "FAIL: eval.options is empty"
            else
              "PASS: eval.options has keys: ${builtins.toJSON (builtins.attrNames opts)}"
        );
      in
      if !result.success then
        "FAIL: evalModules threw exception: ${toString result.value}"
      else
        result.value;

    # Test 2.6: Debug webModule structure
    testWebModuleDebug =
      let
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [ webModule ];
            };
          in
          if !builtins.hasAttr "options" eval then
            "FAIL: eval has no 'options' attr"
          else
            let
              opts = eval.options;
            in
            if opts == { } then
              "FAIL: eval.options is empty"
            else
              "PASS: eval.options has keys: ${builtins.toJSON (builtins.attrNames opts)}"
        );
      in
      if !result.success then
        "FAIL: evalModules threw exception: ${toString result.value}"
      else
        result.value;

    # Test 3: Config applies when both parent and child enabled
    testBothEnabled =
      let
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [
                networkModule
                webModule
                {
                  config.network.enable = true;
                  config.network.services.web.enable = true;
                }
              ];
            };
          in
          if eval.config.network.status != "parent-config-applied" then
            "FAIL: Parent config should be applied when enabled, got: ${eval.config.network.status}"
          else if eval.config.network.services.web.status != "child-config-applied" then
            "FAIL: Child config should be applied when both parent and child enabled, got: ${eval.config.network.services.web.status}"
          else
            "PASS: Both configs applied correctly"
        );
      in
      if !result.success then "FAIL: evalModules failed: ${toString result.value}" else result.value;

    # Test 4: Child config NOT applied when parent disabled
    testParentDisabled =
      let
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [
                networkModule
                webModule
                {
                  config.network.enable = false;
                  config.network.services.web.enable = true;
                }
              ];
            };
          in
          if eval.config.network.services.web.status != "not-applied" then
            "FAIL: Child config should NOT be applied when parent disabled, got status = '${eval.config.network.services.web.status}'"
          else
            "PASS: Parent enable check works"
        );
      in
      if !result.success then "FAIL: evalModules failed: ${toString result.value}" else result.value;

    # Test 5: Child config NOT applied when child disabled
    testChildDisabled =
      let
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [
                networkModule
                webModule
                {
                  config.network.enable = true;
                  config.network.services.web.enable = false;
                }
              ];
            };
          in
          if eval.config.network.services.web.status != "not-applied" then
            "FAIL: Child config should NOT be applied when child disabled, got status = '${eval.config.network.services.web.status}'"
          else
            "PASS: Child enable check works"
        );
      in
      if !result.success then "FAIL: evalModules failed: ${toString result.value}" else result.value;

    # Test 6: Both configs NOT applied when both disabled
    testBothDisabled =
      let
        result = builtins.tryEval (
          let
            eval = lib.evalModules {
              modules = [
                networkModule
                webModule
                {
                  config.network.enable = false;
                  config.network.services.web.enable = false;
                }
              ];
            };
          in
          if eval.config.network.status != "not-applied" then
            "FAIL: Parent config should NOT be applied when disabled, got status = '${eval.config.network.status}'"
          else if eval.config.network.services.web.status != "not-applied" then
            "FAIL: Child config should NOT be applied when both disabled, got status = '${eval.config.network.services.web.status}'"
          else
            "PASS: Both disabled works correctly"
        );
      in
      if !result.success then "FAIL: evalModules failed: ${toString result.value}" else result.value;
  };

in
pkgs.runCommand "check-guarded-nested" { } ''
  echo "=== Debug Info ==="
  echo "moduleCount: ${toString debugChecks.moduleCount}"
  echo "networkInfoFound: ${toString debugChecks.networkInfoFound}"
  echo "webInfoFound: ${toString debugChecks.webInfoFound}"
  echo "networkInfoModPath: ${builtins.toJSON debugChecks.networkInfoModPath}"
  echo "webInfoModPath: ${builtins.toJSON debugChecks.webInfoModPath}"
  echo "guardedTreeChildren: ${toString debugChecks.guardedTreeChildren}"
  echo "childrenModPaths: ${builtins.toJSON debugChecks.childrenModPaths}"
  echo "webInfoParentGuardedPaths: ${builtins.toJSON debugChecks.webInfoParentGuardedPaths}"

  echo ""
  echo "=== Test 0: Verify modules were found ==="
  echo "${checks.testModulesFound}"

  echo ""
  echo "=== Test 1: Verify nested tree structure ==="
  echo "${checks.testNestedStructure}"

  echo ""
  echo "=== Test 2: Verify parentGuardedPaths for nested module ==="
  echo "${checks.testParentGuardedPaths}"

  echo ""
  echo "=== Test 2.5: Debug networkModule ==="
  echo "${checks.testNetworkModuleDebug}"

  echo ""
  echo "=== Test 2.6: Debug webModule ==="
  echo "${checks.testWebModuleDebug}"

  echo ""
  echo "=== Test 3: Config applies when both parent and child enabled ==="
  echo "${checks.testBothEnabled}"

  echo ""
  echo "=== Test 4: Child config NOT applied when parent disabled ==="
  echo "${checks.testParentDisabled}"

  echo ""
  echo "=== Test 5: Child config NOT applied when child disabled ==="
  echo "${checks.testChildDisabled}"

  echo ""
  echo "=== Test 6: Both configs NOT applied when both disabled ==="
  echo "${checks.testBothDisabled}"

  echo ""
  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
