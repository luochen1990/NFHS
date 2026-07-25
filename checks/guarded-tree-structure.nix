# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Module identification and intermediate directory handling
# - Verifies only directories with default.nix are modules
# - Verifies intermediate directories (no default.nix) are NOT modules
# - Verifies .cfg.nix files are correctly scoped to their nearest enclosing module
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
    mkdir -p $out/modules/a/b/c
    mkdir -p $out/modules/d/e

    cat > $out/modules/a/default.nix << 'EOF'
    { lib, ... }: { options.a = lib.mkOption { type = lib.types.str; default = "a-default"; }; }
    EOF
    cat > $out/modules/a/config.cfg.nix << 'EOF'
    { lib, ... }: { config.a = "a-configured"; }
    EOF

    # a/b/c: b 是中间目录（无 default.nix），c 是模块
    cat > $out/modules/a/b/c/default.nix << 'EOF'
    { lib, ... }: { options.a.b.c = lib.mkOption { type = lib.types.str; default = "abc-default"; }; }
    EOF
    cat > $out/modules/a/b/c/config.cfg.nix << 'EOF'
    { lib, ... }: { config.a.b.c = "abc-configured"; }
    EOF

    # d 和 d.e 都是模块
    cat > $out/modules/d/default.nix << 'EOF'
    { lib, ... }: { options.d = lib.mkOption { type = lib.types.str; default = "d-default"; }; }
    EOF
    cat > $out/modules/d/e/default.nix << 'EOF'
    { lib, ... }: { options.d.e = lib.mkOption { type = lib.types.str; default = "de-default"; }; }
    EOF
    cat > $out/modules/d/e/config.cfg.nix << 'EOF'
    { lib, ... }: { config.d.e = "de-configured"; }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";
  allModPaths = map (m: lib.concatStringsSep "." m.modPath) moduleInfos;
  dirCount = lib.length (lib.filter (m: m.kind == "directory") moduleInfos);

  aInfo = lib.findFirst (m: m.modPath == [ "a" ]) null moduleInfos;
  abcInfo = lib.findFirst (m: m.modPath == [ "a" "b" "c" ]) null moduleInfos;
  deInfo = lib.findFirst (m: m.modPath == [ "d" "e" ]) null moduleInfos;

  expectedPaths = [ "a" "a.b.c" "d" "d.e" ];
  sortedGot = lib.sort (a: b: a < b) allModPaths;
  sortedExpected = lib.sort (a: b: a < b) expectedPaths;

  checks = {
    testModuleCount = if dirCount == 4 then "PASS" else "FAIL: expected 4, got ${toString dirCount}";
    testCorrectModules = if sortedGot == sortedExpected then "PASS" else "FAIL: expected ${builtins.toJSON sortedExpected}, got ${builtins.toJSON sortedGot}";
    testAScoping = if aInfo != null && builtins.length aInfo.cfgFiles == 1 then "PASS" else "FAIL: module 'a' scoping wrong";
    testAbcAncestors =
      if abcInfo == null then "FAIL: a.b.c not found"
      else if abcInfo.ancestorModulePaths != [ [ "a" ] ] then "FAIL: expected [[a]], got ${builtins.toJSON abcInfo.ancestorModulePaths}"
      else "PASS";
    testDeAncestors =
      if deInfo == null then "FAIL: d.e not found"
      else if deInfo.ancestorModulePaths != [ [ "d" ] ] then "FAIL: expected [[d]], got ${builtins.toJSON deInfo.ancestorModulePaths}"
      else "PASS";
    testNoIntermediate = if !lib.elem "a.b" allModPaths then "PASS" else "FAIL: a.b should not be a module";
  };

in
mkCheck "module-tree-structure" checks
