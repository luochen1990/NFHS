# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: 目录模块的 .cfg.nix 正确处理 config = lib.mkMerge [...] 写法
#
# 背景: transform 曾用 // 合并 explicit(content.config) 与 implicit(顶层属性),
# 当用户写 `config = lib.mkMerge [...]` 时, explicitConfig 求值为带 _type 标记的
# attrset, 与 implicit 字段扁平拼接会产生畸形结构, 导致 implicit 部分静默丢失,
# 且 mkDefault/mkForce 优先级失效。本测试验证改用 mkMerge 后所有写法均正确。
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
  testSource = pkgs.runCommand "test-source-merge" { } ''
    mkdir -p $out/modules/mergeapp
    cat > $out/modules/mergeapp/default.nix << 'EOF'
    { lib, ... }:
    {
      options.mergeapp = {
        fromMergeExplicit = lib.mkOption { type = lib.types.bool; default = false; };
        fromMergeSecond = lib.mkOption { type = lib.types.bool; default = false; };
        fromImplicit = lib.mkOption { type = lib.types.bool; default = false; };
        priorityWinner = lib.mkOption { type = lib.types.str; default = ""; };
      };
    }
    EOF
    cat > $out/modules/mergeapp/config.cfg.nix << 'EOF'
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

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";
  firstInfo = builtins.head moduleInfos;
  wrappedModule = fhs-modules.wrapModule firstInfo;

  evalEnabled = lib.evalModules {
    modules = [ wrappedModule { config.mergeapp.enable = true; } ];
  };
  evalDisabled = lib.evalModules {
    modules = [ wrappedModule { config.mergeapp.enable = false; } ];
  };
  cfg = evalEnabled.config.mergeapp;
  cfgDisabled = evalDisabled.config.mergeapp;

  checks = {
    testMergeExplicit = if cfg.fromMergeExplicit then "PASS" else "FAIL: fromMergeExpected=true got ${toString cfg.fromMergeExplicit}";
    testMergeSecond = if cfg.fromMergeSecond then "PASS" else "FAIL: fromMergeSecond=true got ${toString cfg.fromMergeSecond}";
    testImplicitMixed = if cfg.fromImplicit then "PASS" else "FAIL: implicit dropped (regression)";
    testPriority = if cfg.priorityWinner == "from-implicit-forced" then "PASS" else "FAIL: expected forced, got '${cfg.priorityWinner}'";
    testDisabledGuard = if !cfgDisabled.fromMergeExplicit && !cfgDisabled.fromImplicit then "PASS" else "FAIL: mkIf guard broken when disabled";
  };

in
mkCheck "guarded-merge" checks
