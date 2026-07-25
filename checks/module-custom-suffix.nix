# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Custom guardedSuffix
# - Verifies custom guardedSuffix works for guarded config files
# - Verifies .nix files (not matching guardedSuffix) are treated as single-file modules
#   when outside any directory module
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
  # 使用自定义 guardedSuffix ".guarded.nix"
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/dir-module

    # 目录模块 + 自定义 guarded 后缀
    cat > $out/modules/dir-module/default.nix << 'EOF'
    { lib, ... }: {
      options.dir-module.setting = lib.mkOption { type = lib.types.str; default = "default"; };
      options.dir-module.active = lib.mkOption { type = lib.types.bool; default = false; };
    }
    EOF
    cat > $out/modules/dir-module/config.guarded.nix << 'EOF'
    { config, ... }: { config.dir-module.active = true; }
    EOF

    # 单文件模块（标准 .nix 后缀，且不在任何目录模块子树内）
    cat > $out/modules/simple.nix << 'EOF'
    { lib, ... }: {
      options.simple.feature = lib.mkOption { type = lib.types.bool; default = true; };
      options.simple.active = lib.mkOption { type = lib.types.bool; default = false; };
      config.simple.active = true;
    }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".guarded.nix";

  modulesOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ (testSource + "/modules") ];
    guardedSuffix = ".guarded.nix";
  };

  moduleNames = builtins.attrNames (builtins.removeAttrs modulesOutput.nixosModules [ "default" ]);

  evalAll = lib.evalModules {
    modules = [
      modulesOutput.nixosModules.default
      { config.dir-module.enable = true; }
    ];
  };

  checks = {
    # 应识别 2 个模块：dir-module (目录模块) + simple (单文件模块)
    t1_counts =
      if builtins.length moduleInfos == 2 then "PASS"
      else "FAIL: expected 2, got ${toString (builtins.length moduleInfos)}";
    t2_outputNames =
      if lib.elem "dir-module" moduleNames && lib.elem "simple" moduleNames then "PASS"
      else "FAIL: got ${builtins.toJSON moduleNames}";
    # 自定义 guardedSuffix 文件被正确收集
    t3_cfgCollected =
      let
        dirInfo = lib.findFirst (m: m.modPath == [ "dir-module" ]) null moduleInfos;
      in
      if dirInfo != null && builtins.length dirInfo.cfgFiles == 1 then "PASS"
      else "FAIL: custom guardedSuffix not collected";
    # 单文件模块总是 active
    t4_singleActive = if evalAll.config.simple.active then "PASS" else "FAIL";
    # 目录模块的 .guarded.nix 在 enable=true 时 active
    t5_dirModuleActive = if evalAll.config.dir-module.active then "PASS" else "FAIL";
  };

in
mkCheck "module-custom-suffix" checks
