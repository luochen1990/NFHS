# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Nested directory modules with enable-chain
# - Verifies nested .cfg.nix checks ALL ancestor module enables
# - Verifies ancestorModulePaths is correctly propagated
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
    mkdir -p $out/modules/network/services/web

    cat > $out/modules/network/default.nix << 'EOF'
    { lib, ... }: { options.network.status = lib.mkOption { type = lib.types.str; default = "not-applied"; }; }
    EOF
    cat > $out/modules/network/config.cfg.nix << 'EOF'
    { config, ... }: { config.network.status = "parent-config-applied"; }
    EOF

    # 注意 services/ 是普通目录（无 default.nix），不进 enable-chain 但贡献 modPath 段
    cat > $out/modules/network/services/web/default.nix << 'EOF'
    { lib, ... }: {
      options.network.services.web = {
        port = lib.mkOption { type = lib.types.int; default = 80; };
        status = lib.mkOption { type = lib.types.str; default = "not-applied"; };
      };
    }
    EOF
    cat > $out/modules/network/services/web/config.cfg.nix << 'EOF'
    { config, ... }: { config.network.services.web.status = "child-config-applied"; }
    EOF
  '';

  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".cfg.nix";

  networkInfo = lib.findFirst (m: m.modPath == [ "network" ]) null moduleInfos;
  webInfo = lib.findFirst (m: m.modPath == [ "network" "services" "web" ]) null moduleInfos;

  networkModule = fhs-modules.wrapModule networkInfo;
  webModule = fhs-modules.wrapModule webInfo;

  # evaluate 在不同 enable 组合下的行为
  eval =
    networkEnable: webEnable:
    let
      r = builtins.tryEval (lib.evalModules {
          modules = [
            networkModule
            webModule
            {
              config.network.enable = networkEnable;
              config.network.services.web.enable = webEnable;
            }
          ];
        }).config;
    in
    if r.success then r.value else { __error = true; msg = toString r.value; };

  checks = {
    testModulesFound =
      if networkInfo == null then "FAIL: network not found"
      else if webInfo == null then "FAIL: web not found"
      else "PASS";

    testAncestorModulePaths =
      if webInfo.ancestorModulePaths != [ [ "network" ] ] then
        "FAIL: expected [[network]], got ${builtins.toJSON webInfo.ancestorModulePaths}"
      else "PASS";

    testBothEnabled =
      let c = eval true true; in
      if c ? __error then "FAIL: eval error: ${c.msg}"
      else if c.network.status != "parent-config-applied" then "FAIL: parent not applied: ${c.network.status}"
      else if c.network.services.web.status != "child-config-applied" then "FAIL: child not applied: ${c.network.services.web.status}"
      else "PASS";

    testParentDisabled =
      let c = eval false true; in
      if c ? __error then "FAIL: eval error: ${c.msg}"
      else if c.network.services.web.status != "not-applied" then "FAIL: child should not apply: ${c.network.services.web.status}"
      else "PASS";

    testChildDisabled =
      let c = eval true false; in
      if c ? __error then "FAIL: eval error: ${c.msg}"
      else if c.network.services.web.status != "not-applied" then "FAIL: child should not apply: ${c.network.services.web.status}"
      else "PASS";

    testBothDisabled =
      let c = eval false false; in
      if c ? __error then "FAIL: eval error: ${c.msg}"
      else if c.network.status != "not-applied" then "FAIL: parent should not apply: ${c.network.status}"
      else if c.network.services.web.status != "not-applied" then "FAIL: child should not apply: ${c.network.services.web.status}"
      else "PASS";
  };

in
mkCheck "guarded-nested" checks
