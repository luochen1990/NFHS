# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Basic directory module with guarded config files
# - Verifies enable option auto-generation for directory modules
# - Verifies .cfg.nix files are wrapped with mkIf(enable-chain)
# - Verifies default.nix config is always applied (no mkIf)
# - Verifies module is exported correctly
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
  # 新结构: 目录模块用 default.nix + .cfg.nix
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/myapp
    cat > $out/modules/myapp/default.nix << 'EOF'
    { lib, ... }:
    {
      options.myapp = {
        message = lib.mkOption { type = lib.types.str; default = "hello"; };
        status = lib.mkOption { type = lib.types.str; default = "not-applied"; };
      };
    }
    EOF
    cat > $out/modules/myapp/config.cfg.nix << 'EOF'
    { config, lib, ... }:
    {
      config.myapp.status = "config-applied";
    }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";
  firstInfo = builtins.head moduleInfos;
  wrappedModule = fhs-modules.wrapModule firstInfo;

  evalResult = lib.evalModules {
    modules = [
      wrappedModule
      { config.myapp.enable = true; }
    ];
  };

  evalDisabled = lib.evalModules {
    modules = [
      wrappedModule
      { config.myapp.enable = false; }
    ];
  };

  checks = {
    testModuleCount =
      if builtins.length moduleInfos != 1 then
        "FAIL: Expected 1 module, got ${toString (builtins.length moduleInfos)}"
      else "PASS: Module collected";
    testModuleKind =
      if firstInfo.kind != "directory" then
        "FAIL: Expected kind 'directory', got '${firstInfo.kind}'"
      else "PASS: Module kind is directory";
    testEnableExists =
      if !(builtins.hasAttr "enable" evalResult.options.myapp) then
        "FAIL: Enable option not found. Available: ${builtins.concatStringsSep ", " (builtins.attrNames evalResult.options.myapp)}"
      else "PASS: Enable option auto-injected";
    testConfigResult =
      if evalResult.config.myapp.status != "config-applied" then
        "FAIL: Expected status='config-applied', got '${toString evalResult.config.myapp.status}'"
      else "PASS: .cfg.nix config applied when enabled";
    testDisabledConfig =
      if evalDisabled.config.myapp.status != "not-applied" then
        "FAIL: .cfg.nix should NOT apply when disabled, got '${toString evalDisabled.config.myapp.status}'"
      else "PASS: .cfg.nix correctly guarded by enable";
  };

in
mkCheck "directory-basic" checks
