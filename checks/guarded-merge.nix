# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: guarded module 正确处理 config = lib.mkMerge [...] 写法
#
# 背景: transform 曾用 // 合并 explicit(content.config) 与 implicit(顶层属性),
# 当用户写 `config = lib.mkMerge [...]` 时, explicitConfig 求值为带 _type 标记的
# attrset, 与 implicit 字段扁平拼接会产生畸形结构, 导致 implicit 部分静默丢失,
# 且 mkDefault/mkForce 优先级失效。本测试验证改用 mkMerge 后所有写法均正确。
#
# 覆盖场景:
#   1. mkMerge 单元素生效
#   2. mkMerge 多元素均生效
#   3. mkMerge + 顶层 implicit 混用均生效 (核心 bug 回归保护)
#   4. mkForce 跨 explicit/implicit 分片正确仲裁优先级
#   5. enable=false 时 mkMerge 配置整体不被应用
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # 构建测试用 guarded module: 同时使用 mkMerge 和顶层 implicit 写法
  testSource = pkgs.runCommand "test-source-merge" { } ''
    mkdir -p $out/modules/mergeapp
    # options.nix
    cat > $out/modules/mergeapp/options.nix << 'EOF'
    { lib, ... }:
    {
      options.mergeapp = {
        fromMergeExplicit = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        fromMergeSecond = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        fromImplicit = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        priorityWinner = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };
    }
    EOF
    # config.nix: 混用 config = mkMerge [...] 和顶层 implicit 属性
    cat > $out/modules/mergeapp/config.nix << 'EOF'
    { lib, ... }:
    {
      config = lib.mkMerge [
        { mergeapp.fromMergeExplicit = true; }
        { mergeapp.fromMergeSecond = true; }
        { mergeapp.priorityWinner = "from-merge-normal"; }
      ];
      # implicit 顶层属性 (修复前会被静默丢弃)
      mergeapp.fromImplicit = true;
      # implicit 端用 mkForce, 应在优先级仲裁中胜过 explicit 端的普通值
      mergeapp.priorityWinner = lib.mkForce "from-implicit-forced";
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

  # Evaluate with enable = true
  evalEnabled = lib.evalModules {
    modules = [
      wrappedModule
      { config.mergeapp.enable = true; }
    ];
  };

  # Evaluate with enable = false (验证 mkIf 包裹仍生效)
  evalDisabled = lib.evalModules {
    modules = [
      wrappedModule
      { config.mergeapp.enable = false; }
    ];
  };

  cfg = evalEnabled.config.mergeapp;
  cfgDisabled = evalDisabled.config.mergeapp;

  # Test checks (computed at eval time)
  checks = {
    # Test 1: mkMerge 单元素生效
    testMergeExplicit =
      if !cfg.fromMergeExplicit then
        "FAIL: Expected fromMergeExplicit = true, got ${toString cfg.fromMergeExplicit}"
      else
        "PASS: mkMerge single element applied";

    # Test 2: mkMerge 多元素均生效
    testMergeSecond =
      if !cfg.fromMergeSecond then
        "FAIL: Expected fromMergeSecond = true, got ${toString cfg.fromMergeSecond}"
      else
        "PASS: mkMerge multiple elements applied";

    # Test 3: mkMerge + 顶层 implicit 混用 (核心 bug 回归)
    testImplicitMixed =
      if !cfg.fromImplicit then
        "FAIL: Expected fromImplicit = true (implicit must not be silently dropped), got ${toString cfg.fromImplicit}"
      else
        "PASS: implicit config preserved alongside mkMerge";

    # Test 4: mkForce 跨 explicit/implicit 分片优先级仲裁
    testPriority =
      if cfg.priorityWinner != "from-implicit-forced" then
        "FAIL: Expected priorityWinner = 'from-implicit-forced' (mkForce should win), got '${cfg.priorityWinner}'"
      else
        "PASS: mkForce priority correctly resolved across merge slices";

    # Test 5: enable=false 时 mkMerge 配置整体不被应用
    testDisabledGuard =
      if cfgDisabled.fromMergeExplicit || cfgDisabled.fromImplicit then
        "FAIL: Config should NOT be applied when disabled (fromMergeExplicit=${toString cfgDisabled.fromMergeExplicit}, fromImplicit=${toString cfgDisabled.fromImplicit})"
      else
        "PASS: mkMerge config correctly guarded by mkIf";
  };

in
pkgs.runCommand "check-guarded-merge" { } ''
  echo "=== Test 1: mkMerge single element ==="
  echo "${checks.testMergeExplicit}"

  echo ""
  echo "=== Test 2: mkMerge multiple elements ==="
  echo "${checks.testMergeSecond}"

  echo ""
  echo "=== Test 3: mkMerge + implicit mixed (core bug regression) ==="
  echo "${checks.testImplicitMixed}"

  echo ""
  echo "=== Test 4: mkForce priority across slices ==="
  echo "${checks.testPriority}"

  echo ""
  echo "=== Test 5: disabled config guard ==="
  echo "${checks.testDisabledGuard}"

  echo ""
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    echo "=== Some tests FAILED ==="
    exit 1
  fi

  echo "=== All tests passed ==="
  touch $out
''
