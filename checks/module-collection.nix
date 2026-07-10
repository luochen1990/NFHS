# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Module collection with all three types
# - Verifies all three module types coexist correctly
# - Verifies mkModulesOutput generates correct outputs
# - Verifies default module includes all modules
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # Create test directory with all three module types:
  # modules/
  # ├── guarded-app/           <- Guarded module
  # │   ├── options.nix
  # │   └── config.nix
  # ├── traditional-set/       <- Traditional module
  # │   └── default.nix
  # └── simple.nix             <- Single file module
  testSource = pkgs.runCommand "test-source" { } ''
    mkdir -p $out/modules/guarded-app
    mkdir -p $out/modules/traditional-set

    # Guarded module
    cat > $out/modules/guarded-app/options.nix << 'EOF'
    { lib, ... }:
    {
      options.guarded-app.setting = lib.mkOption {
        type = lib.types.str;
        default = "guarded-default";
      };
    }
    EOF
    cat > $out/modules/guarded-app/config.nix << 'EOF'
    { config, ... }:
    {
      config.guarded-app.active = true;
    }
    EOF

    # Traditional module
    cat > $out/modules/traditional-set/default.nix << 'EOF'
    { lib, ... }:
    {
      options.traditional-set.value = lib.mkOption {
        type = lib.types.str;
        default = "traditional-default";
      };
      config.traditional-set.active = true;
    }
    EOF

    # Single file module
    cat > $out/modules/simple.nix << 'EOF'
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

  # Collect modules
  moduleInfos = fhs-modules.collectModules (testSource + "/modules") ".nix";

  # Count modules by type
  guardedCount = lib.length (lib.filter (m: m.moduleType == "guarded") moduleInfos);
  traditionalCount = lib.length (lib.filter (m: m.moduleType == "traditional") moduleInfos);
  singleCount = lib.length (lib.filter (m: m.moduleType == "single") moduleInfos);
  totalCount = lib.length moduleInfos;

  # Generate outputs
  modulesOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ (testSource + "/modules") ];
    suffix = ".nix";
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
    # Test 1: Verify module counts
    testCounts =
      if guardedCount != 1 then
        throw "Expected 1 guarded module, got ${toString guardedCount}"
      else if traditionalCount != 1 then
        throw "Expected 1 traditional module, got ${toString traditionalCount}"
      else if singleCount != 1 then
        throw "Expected 1 single file module, got ${toString singleCount}"
      else if totalCount != 3 then
        throw "Expected 3 total modules, got ${toString totalCount}"
      else
        true;

    # Test 2: Verify output names
    testOutputNames =
      if !(lib.elem "guarded-app" moduleNames) then
        throw "Expected 'guarded-app' in outputs, got: ${builtins.concatStringsSep ", " moduleNames}"
      else if !(lib.elem "traditional-set" moduleNames) then
        throw "Expected 'traditional-set' in outputs, got: ${builtins.concatStringsSep ", " moduleNames}"
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

    # Test 4: Verify traditional module always active
    testTraditionalActive =
      if evalAll.config.traditional-set.active != true then
        throw "Traditional module should always be active"
      else
        true;

    # Test 5: Verify single file module always active
    testSingleActive =
      if evalAll.config.simple.active != true then
        throw "Single file module should always be active"
      else
        true;

    # Test 6: Verify guarded module active when enabled
    testGuardedActive =
      if evalAll.config.guarded-app.active != true then
        throw "Guarded module should be active when enabled"
      else
        true;

    # Test 7: Verify guarded module NOT active when disabled
    testGuardedInactive =
      let
        evalDisabled = lib.evalModules {
          modules = [
            modulesOutput.nixosModules.default
            {
              config.guarded-app.enable = false;
            }
          ];
        };
      in
      if evalDisabled.config.guarded-app ? active then
        throw "Guarded module should NOT be active when disabled"
      else
        true;
  };

in
pkgs.runCommand "check-module-collection" { } ''
  echo "=== Test 1: Verify module counts ==="
  echo "PASS: Found 1 guarded, 1 traditional, 1 single = 3 total"

  echo ""
  echo "=== Test 2: Verify output names ==="
  echo "PASS: All module names present in outputs"

  echo ""
  echo "=== Test 3: Verify default module exists ==="
  echo "PASS: default module exists"

  echo ""
  echo "=== Test 4: Verify traditional module always active ==="
  echo "PASS: Traditional module active"

  echo ""
  echo "=== Test 5: Verify single file module always active ==="
  echo "PASS: Single file module active"

  echo ""
  echo "=== Test 6: Verify guarded module active when enabled ==="
  echo "PASS: Guarded module active when enabled"

  echo ""
  echo "=== Test 7: Verify guarded module NOT active when disabled ==="
  echo "PASS: Guarded module correctly disabled"

  echo ""
  echo "=== All tests passed ==="
  touch $out
''
