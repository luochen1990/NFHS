# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: strictOptions post-evaluation validation
#
# 测试 namespace 校验基础设施:
#   - collectOptionLeaves: 遍历已求值的 options 树
#   - validateOptionNamespaces: 识别违规
#   - mkStrictValidationModule: 生成 assertions
#   - mkModulesOutput 集成 (启用/禁用)
#
# 新结构: options 写在目录模块的 default.nix 里（不再是 options.nix 信号文件）
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  mkCheck,
  ...
}:

let
  # ================================================================
  # Test fixtures: 新结构，options 写在 default.nix 里
  # ================================================================
  testSource = pkgs.runCommand "strict-test-source" { } ''
    mkdir -p $out/modules/foo
    mkdir -p $out/modules/wrongns
    mkdir -p $out/modules/nested/child
    mkdir -p $out/modules/empty

    # foo/default.nix: 正确命名空间 (options.foo.*)
    cat > $out/modules/foo/default.nix << 'EOF'
    { lib, ... }: {
      options.foo = {
        setting = lib.mkOption { type = lib.types.str; default = "hello"; };
        result = lib.mkOption { type = lib.types.str; default = ""; };
      };
    }
    EOF
    # foo/config.cfg.nix: guarded config
    cat > $out/modules/foo/config.cfg.nix << 'EOF'
    { config, lib, ... }: {
      config.foo.result = lib.mkIf config.foo.enable config.foo.setting;
    }
    EOF

    # wrongns/default.nix: 错误命名空间 (定义 options.bad 而非 options.wrongns)
    cat > $out/modules/wrongns/default.nix << 'EOF'
    { lib, ... }: {
      options.bad = {
        enable = lib.mkEnableOption "bad";
      };
    }
    EOF

    # nested/child/default.nix: 正确嵌套命名空间 (options.nested.child.*)
    cat > $out/modules/nested/child/default.nix << 'EOF'
    { lib, ... }: {
      options.nested.child = {
        enable = lib.mkEnableOption "child";
      };
    }
    EOF

    # empty/default.nix: 空目录模块 (只有自动注入的 enable)
    cat > $out/modules/empty/default.nix << 'EOF'
    { lib, ... }: {
    }
    EOF
  '';

  modulesRoot = testSource + "/modules";

  # Module infos matching the fixture structure
  manualInfos = [
    { path = modulesRoot + "/foo"; modPath = [ "foo" ]; }
    { path = modulesRoot + "/wrongns"; modPath = [ "wrongns" ]; }
    { path = modulesRoot + "/nested/child"; modPath = [ "nested" "child" ]; }
    { path = modulesRoot + "/empty"; modPath = [ "empty" ]; }
  ];

  # ================================================================
  # Test 1: collectOptionLeaves — walks evaluated options tree
  # ================================================================
  collectTestEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/default.nix")
      (modulesRoot + "/wrongns/default.nix")
    ];
  };

  collectLeaves = fhs-modules.collectOptionLeaves collectTestEval.options;
  leafLocs = map (leaf: leaf.loc) collectLeaves;

  # ================================================================
  # Test 2: validateOptionNamespaces — identifies violations
  # ================================================================
  validationEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/default.nix")
      (modulesRoot + "/wrongns/default.nix")
      (modulesRoot + "/nested/child/default.nix")
    ];
  };

  violations = fhs-modules.validateOptionNamespaces manualInfos validationEval.options;
  violationLocs = map (v: v.loc) violations;

  # ================================================================
  # Test 3: mkStrictValidationModule — produces assertions
  # ================================================================
  assertionsEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/default.nix")
      (modulesRoot + "/wrongns/default.nix")
      (fhs-modules.mkStrictValidationModule manualInfos)
    ];
  };

  allAssertions = assertionsEval.config.assertions or [ ];
  failedAssertions = builtins.filter (a: !a.assertion) allAssertions;

  # ================================================================
  # Test 4: Cross-namespace options are flagged (flake-fhs convention)
  # ================================================================
  crossNsSource = pkgs.runCommand "cross-ns-test" { } ''
    mkdir -p $out/modules/foo
    cat > $out/modules/foo/default.nix << 'EOF'
    { lib, ... }: {
      options.foo.enable = lib.mkEnableOption "foo";
      options.services.integration = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    }
    EOF
  '';

  crossNsInfos = [
    { path = crossNsSource + "/modules/foo"; modPath = [ "foo" ]; }
  ];

  crossNsEval = lib.evalModules {
    modules = [
      (crossNsSource + "/modules/foo/default.nix")
      (fhs-modules.mkStrictValidationModule crossNsInfos)
    ];
  };

  crossNsFailed = builtins.filter (a: !a.assertion) (crossNsEval.config.assertions or [ ]);

  # ================================================================
  # Test 5: strictOptions disabled by default
  # ================================================================
  noStrictOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ modulesRoot ];
    guardedSuffix = ".cfg.nix";
    strictOptions = false;
  };

  noStrictEval = lib.evalModules {
    modules = [ noStrictOutput.nixosModules.default ];
  };

  noStrictFailed = builtins.filter (a: !a.assertion) (noStrictEval.config.assertions or [ ]);

  # ================================================================
  # Test 6: strictOptions enabled end-to-end via mkModulesOutput
  # ================================================================
  strictOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ modulesRoot ];
    guardedSuffix = ".cfg.nix";
    strictOptions = true;
  };

  strictEval = lib.evalModules {
    modules = [ strictOutput.nixosModules.default ];
  };

  strictFailed = builtins.filter (a: !a.assertion) (strictEval.config.assertions or [ ]);

  # ================================================================
  # Compute test results
  # ================================================================
  has = loc: locs: builtins.any (l: l == loc) locs;

  checks = {
    # --- Test 1: collectOptionLeaves ---
    # foo 有 foo.setting 和 foo.result（直接 import options，没经过 wrap，所以无 auto enable）
    # wrongns 有 bad.enable
    t1_count =
      if builtins.length collectLeaves == 3 then "PASS"
      else "FAIL: expected 3 leaves got ${toString (builtins.length collectLeaves)}";
    t1_foo_setting =
      if has [ "foo" "setting" ] leafLocs then "PASS"
      else "FAIL: foo.setting not found";
    t1_bad_enable =
      if has [ "bad" "enable" ] leafLocs then "PASS"
      else "FAIL: bad.enable not found";

    # --- Test 2: validateOptionNamespaces ---
    t2_foo_ok =
      if !(has [ "foo" "setting" ] violationLocs) then "PASS"
      else "FAIL: foo should not be in violations";
    t2_nested_ok =
      if !(has [ "nested" "child" "enable" ] violationLocs) then "PASS"
      else "FAIL: nested.child should not be in violations";
    t2_bad_caught =
      if has [ "bad" "enable" ] violationLocs then "PASS"
      else "FAIL: bad.enable should be in violations";
    t2_count =
      if builtins.length violations == 1 then "PASS"
      else "FAIL: expected 1 violation got ${toString (builtins.length violations)}";

    # --- Test 3: mkStrictValidationModule ---
    t3_count =
      if builtins.length failedAssertions == 1 then "PASS"
      else "FAIL: expected 1 failed assertion got ${toString (builtins.length failedAssertions)}";
    t3_message =
      let
        msg = if failedAssertions != [ ] then (builtins.head failedAssertions).message else "";
        mentionsBoth = builtins.match ".*bad.*wrongns.*" msg != null
          || builtins.match ".*wrongns.*bad.*" msg != null;
      in
      if mentionsBoth then "PASS"
      else "FAIL: assertion message does not mention both bad and wrongns";

    # --- Test 4: cross-namespace allowed ---
    t4_cross_flagged =
      if crossNsFailed != [ ] then "PASS"
      else "FAIL: cross-namespace should be flagged";

    # --- Test 5: disabled by default ---
    t5_no_assertions =
      if noStrictFailed == [ ] then "PASS"
      else "FAIL: should have no assertions when disabled";

    # --- Test 6: enabled end-to-end ---
    t6_active =
      if builtins.length strictFailed == 1 then "PASS"
      else "FAIL: expected 1 violation with strictOptions got ${toString (builtins.length strictFailed)}";
  };

in
mkCheck "strict-options" checks
