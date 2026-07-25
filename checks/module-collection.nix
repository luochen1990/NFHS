# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Module collection with all module kinds
# - Verifies directory modules (with/without .cfg.nix) and single file modules coexist
# - Verifies mkModulesOutput generates correct outputs
# - Verifies default module includes all modules
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
    mkdir -p $out/modules/guarded-app
    mkdir -p $out/modules/traditional-set

    cat > $out/modules/guarded-app/default.nix << 'EOF'
    { lib, ... }: {
      options.guarded-app.setting = lib.mkOption { type = lib.types.str; default = "guarded-default"; };
      options.guarded-app.active = lib.mkOption { type = lib.types.bool; default = false; };
    }
    EOF
    cat > $out/modules/guarded-app/config.cfg.nix << 'EOF'
    { config, ... }: { config.guarded-app.active = true; }
    EOF

    cat > $out/modules/traditional-set/default.nix << 'EOF'
    { lib, ... }: {
      options.traditional-set.value = lib.mkOption { type = lib.types.str; default = "traditional-default"; };
      options.traditional-set.active = lib.mkOption { type = lib.types.bool; default = false; };
      config.traditional-set.active = true;
    }
    EOF

    cat > $out/modules/simple.nix << 'EOF'
    { lib, ... }: {
      options.simple.feature = lib.mkOption { type = lib.types.bool; default = true; };
      options.simple.active = lib.mkOption { type = lib.types.bool; default = false; };
      config.simple.active = true;
    }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";

  dirWithCfg = lib.length (lib.filter (m: m.kind == "directory" && m.cfgFiles != [ ]) moduleInfos);
  dirWithoutCfg = lib.length (lib.filter (m: m.kind == "directory" && m.cfgFiles == [ ]) moduleInfos);
  singleCount = lib.length (lib.filter (m: m.kind == "file") moduleInfos);

  modulesOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ (testSource + "/modules") ];
    guardedSuffix = ".cfg.nix";
  };

  moduleNames = builtins.attrNames (builtins.removeAttrs modulesOutput.nixosModules [ "default" ]);

  evalAll = lib.evalModules {
    modules = [
      modulesOutput.nixosModules.default
      { config.guarded-app.enable = true; }
    ];
  };

  evalDisabled = lib.evalModules {
    modules = [
      modulesOutput.nixosModules.default
      { config.guarded-app.enable = false; }
    ];
  };

  checks = {
    t1_counts =
      if dirWithCfg == 1 && dirWithoutCfg == 1 && singleCount == 1 then "PASS"
      else "FAIL: expected (1,1,1) got (${toString dirWithCfg},${toString dirWithoutCfg},${toString singleCount})";
    t2_outputNames =
      if lib.elem "guarded-app" moduleNames && lib.elem "traditional-set" moduleNames && lib.elem "simple" moduleNames then "PASS"
      else "FAIL: got ${builtins.toJSON moduleNames}";
    t3_defaultExists = if builtins.hasAttr "default" modulesOutput.nixosModules then "PASS" else "FAIL";
    t4_traditionalActive = if evalAll.config.traditional-set.active then "PASS" else "FAIL";
    t5_singleActive = if evalAll.config.simple.active then "PASS" else "FAIL";
    t6_guardedActive = if evalAll.config.guarded-app.active then "PASS" else "FAIL";
    t7_guardedInactive = if !evalDisabled.config.guarded-app.active then "PASS" else "FAIL";
  };

in
mkCheck "module-collection" checks
