# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Single file module functionality
# - Verifies standalone .nix files are recognized as modules (when NOT inside any directory module subtree)
# - Verifies .nix files INSIDE a directory module subtree are NOT recognized (managed by default.nix)
# - Verifies no enable injection for single file modules
# - Verifies config is always applied
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
    mkdir -p $out/modules/helpers
    mkdir -p $out/modules/dirmod/sub

    # 单文件模块（根目录下，不在任何目录模块子树内）
    cat > $out/modules/utils.nix << 'EOF'
    { lib, ... }:
    {
      options.utils.feature = lib.mkEnableOption "utils feature";
      config.utils.feature = true;
    }
    EOF

    # 单文件模块在普通子目录下（helpers 无 default.nix，不在任何模块子树内）
    cat > $out/modules/helpers/common.nix << 'EOF'
    { lib, ... }:
    {
      options.helpers.common.setting = lib.mkOption { type = lib.types.bool; default = false; };
      config.helpers.common.setting = true;
    }
    EOF

    # 目录模块 dirmod
    cat > $out/modules/dirmod/default.nix << 'EOF'
    { lib, ... }: {
      options.dirmod.value = lib.mkOption { type = lib.types.str; default = "dirmod"; };
    }
    EOF

    # dirmod/sub/internal.nix 在目录模块子树内，不应被识别为单文件模块
    cat > $out/modules/dirmod/sub/internal.nix << 'EOF'
    { lib, ... }: {
      options.internal.value = lib.mkOption { type = lib.types.str; default = "should-not-load"; };
    }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";

  utilsInfo = lib.findFirst (m: m.modPath == [ "utils" ]) null moduleInfos;
  commonInfo = lib.findFirst (m: m.modPath == [ "helpers" "common" ]) null moduleInfos;
  dirmodInfo = lib.findFirst (m: m.modPath == [ "dirmod" ]) null moduleInfos;

  allModPaths = map (m: lib.concatStringsSep "." m.modPath) moduleInfos;

  utilsEval = lib.evalModules { modules = [ (fhs-modules.wrapModule utilsInfo) ]; };
  commonEval = lib.evalModules { modules = [ (fhs-modules.wrapModule commonInfo) ]; };

  checks = {
    # 应识别 3 个模块：utils (单文件), helpers.common (单文件), dirmod (目录)
    # 注意 dirmod.sub.internal 不应被识别（在 dirmod 目录模块子树内）
    testCount =
      let count = builtins.length moduleInfos; in
      if count == 3 then "PASS"
      else "FAIL: expected 3 (dirmod.sub.internal must be excluded), got ${toString count}: ${builtins.toJSON allModPaths}";

    testNoInternalModule =
      if !lib.elem "dirmod.sub.internal" allModPaths then "PASS"
      else "FAIL: dirmod.sub.internal should NOT be a module (inside dirmod subtree)";

    testUtilsKind = if utilsInfo.kind == "file" then "PASS" else "FAIL: got '${utilsInfo.kind}'";
    testCommonModPath = if builtins.concatStringsSep "." commonInfo.modPath == "helpers.common" then "PASS" else "FAIL";
    testDirmodKind = if dirmodInfo.kind == "directory" then "PASS" else "FAIL: got '${dirmodInfo.kind}'";

    testUtilsConfig = if utilsEval.config.utils.feature then "PASS" else "FAIL: config not applied";
    testCommonConfig = if commonEval.config.helpers.common.setting then "PASS" else "FAIL: config not applied";

    testNoAutoEnable = if !builtins.hasAttr "enable" utilsEval.options.utils then "PASS" else "FAIL: enable should not be injected";
  };

in
mkCheck "single-file" checks
