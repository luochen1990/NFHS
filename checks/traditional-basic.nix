# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Directory module without guarded config (was "traditional module")
# - Verifies module with only default.nix (no .cfg.nix) is directly exported
# - Verifies enable is still injected (all directory modules get enable)
# - Verifies config in default.nix is always applied (no mkIf)
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
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/configs
    cat > $out/modules/configs/default.nix << 'EOF'
    { lib, ... }:
    {
      options.configs.setting1 = lib.mkOption { type = lib.types.str; default = "default-value"; };
      options.configs.setting2 = lib.mkOption { type = lib.types.str; default = ""; };
      config.configs.setting2 = "always-set";
    }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";
  configsInfo = builtins.head moduleInfos;
  configsModule = fhs-modules.wrapModule configsInfo;
  evalResult = lib.evalModules { modules = [ configsModule ]; };

  checks = {
    testModuleKind = if configsInfo.kind == "directory" then "PASS" else "FAIL: got '${configsInfo.kind}'";
    testNoCfgFiles = if configsInfo.cfgFiles == [ ] then "PASS" else "FAIL: expected empty cfgFiles";
    testModPath = if builtins.concatStringsSep "." configsInfo.modPath == "configs" then "PASS" else "FAIL: got '${builtins.concatStringsSep "." configsInfo.modPath}'";
    testConfigAlwaysApplied = if evalResult.config.configs.setting2 == "always-set" then "PASS" else "FAIL: default.nix config not applied";
    testEnableInjected = if builtins.hasAttr "enable" evalResult.options.configs then "PASS" else "FAIL: enable not injected";
    testUserOptions = if evalResult.config.configs.setting1 == "default-value" then "PASS" else "FAIL: user option broken";
  };

in
mkCheck "traditional-basic" checks
