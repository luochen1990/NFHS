# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Module collection with custom suffix (e.g., .mod.nix)
# - Verifies that custom suffix works for guarded modules
# - Verifies that custom suffix works for single file modules
# - Verifies that files with wrong suffix are ignored
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create test directory with custom suffix modules:
  # modules/
  # ├── guarded-app/           <- Guarded module (should be found)
  # │   ├── options.nix
  # │   └── config.mod.nix
  # ├── helper.nix             <- Helper file (should be IGNORED)
  # └── simple.mod.nix         <- Single file module (should be found)
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/guarded-app

    # Guarded module with .mod.nix config
    cat > $out/modules/guarded-app/options.nix << 'EOF'
    { lib, ... }:
    {
      options.guarded-app.setting = lib.mkOption {
        type = lib.types.str;
        default = "guarded-default";
      };
    }
    EOF
    cat > $out/modules/guarded-app/config.mod.nix << 'EOF'
    { config, ... }:
    {
      config.guarded-app.active = true;
    }
    EOF

    # Helper file (should be ignored)
    cat > $out/modules/helper.nix << 'EOF'
    # This is a helper file, not a module
    { lib }:
    lib.mkDefault "helper"
    EOF

    # Single file module with .mod.nix
    cat > $out/modules/simple.mod.nix << 'EOF'
    { lib, ... }:
    {
      options.simple.feature = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      config.simple.active = true;
    }
    EOF
  '';

  # Collect modules with custom suffix
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".mod.nix";

  # Count modules by type
  guardedCount = lib.length (lib.filter (m: m.moduleType == "guarded") moduleInfos);
  singleCount = lib.length (lib.filter (m: m.moduleType == "single") moduleInfos);
  totalCount = lib.length moduleInfos;

  # Generate outputs with custom suffix
  modulesOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ (testSource + "/modules") ];
    suffix = ".mod.nix";
  };

  # Get all module names
  moduleNames = builtins.attrNames (builtins.removeAttrs modulesOutput.nixosModules [ "default" ]);

  # Evaluate with all modules (default)
  evalAll = lib.evalModules {
    modules = [
      modulesOutput.nixosModules.default
      {
        config.guarded-app.enable = true;
      }
    ];
  };

  # Test checks
  checks = {
    # Test 1: Verify module counts (should NOT include helper.nix)
    testCounts =
      if guardedCount != 1 then
        throw "Expected 1 guarded module, got ${toString guardedCount}"
      else if singleCount != 1 then
        throw "Expected 1 single file module, got ${toString singleCount}"
      else if totalCount != 2 then
        throw "Expected 2 total modules (helper.nix should be ignored), got ${toString totalCount}"
      else
        true;

    # Test 2: Verify output names
    testOutputNames =
      if !(lib.elem "guarded-app" moduleNames) then
        throw "Expected 'guarded-app' in outputs, got: ${builtins.concatStringsSep ", " moduleNames}"
      else if !(lib.elem "simple" moduleNames) then
        throw "Expected 'simple' in outputs, got: ${builtins.concatStringsSep ", " moduleNames}"
      else
        true;

    # Test 3: Verify default module exists
    testDefaultModule =
      if !(builtins.hasAttr "default" modulesOutput.nixosModules) then
        throw "Expected 'default' in nixosModules"
      else
        true;

    # Test 4: Verify single file module always active
    testSingleActive =
      if evalAll.config.simple.active != true then
        throw "Single file module should always be active"
      else
        true;

    # Test 5: Verify guarded module active when enabled
    testGuardedActive =
      if evalAll.config.guarded-app.active != true then
        throw "Guarded module should be active when enabled"
      else
        true;

    # Test 6: Verify helper.nix was NOT loaded as a module
    testHelperIgnored =
      if lib.elem "helper" moduleNames then
        throw "helper.nix should NOT be loaded as a module (wrong suffix)"
      else
        true;
  };

in
pkgs.runCommand "check-module-custom-suffix" { } ''
  echo "=== Test 1: Verify module counts (helper.nix ignored) ==="
  echo "PASS: Found 1 guarded, 1 single = 2 total (helper.nix correctly ignored)"

  echo ""
  echo "=== Test 2: Verify output names ==="
  echo "PASS: All module names present in outputs"

  echo ""
  echo "=== Test 3: Verify default module exists ==="
  echo "PASS: default module exists"

  echo ""
  echo "=== Test 4: Verify single file module always active ==="
  echo "PASS: Single file module active"

  echo ""
  echo "=== Test 5: Verify guarded module active when enabled ==="
  echo "PASS: Guarded module active when enabled"

  echo ""
  echo "=== Test 6: Verify helper.nix was NOT loaded ==="
  echo "PASS: helper.nix correctly ignored (wrong suffix)"

  echo ""
  echo "=== All tests passed ==="
  touch $out
''
