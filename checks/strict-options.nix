# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: strictOptions post-evaluation validation
#
# Tests the namespace validation infrastructure:
#   - collectOptionLeaves: walks evaluated options tree
#   - validateOptionNamespaces: identifies violations
#   - mkStrictValidationModule: produces assertions
#   - mkModulesOutput integration (enabled/disabled)
#
{
  pkgs,
  lib,
  self,
  fhs-modules,
  ...
}:

let
  # ================================================================
  # Test fixtures: directory structures in the Nix store
  # ================================================================

  testSource = pkgs.runCommand "strict-test-source" { } ''
    mkdir -p $out/modules/foo
    mkdir -p $out/modules/wrongns
    mkdir -p $out/modules/nested/child
    mkdir -p $out/modules/empty

    # foo/options.nix: correctly namespaced under foo
    cat > $out/modules/foo/options.nix << 'EOF'
    { lib, ... }: {
      options.foo = {
        enable = lib.mkEnableOption "foo";
        setting = lib.mkOption { type = lib.types.str; default = "hello"; };
        result = lib.mkOption { type = lib.types.str; default = ""; };
      };
    }
    EOF

    # foo/config.nix: config referencing options (uses lib)
    cat > $out/modules/foo/config.nix << 'EOF'
    { config, lib, ... }: {
      config.foo.result = lib.mkIf config.foo.enable config.foo.setting;
    }
    EOF

    # wrongns/options.nix: INCORRECTLY namespaced (defines options.bad, not options.wrongns)
    cat > $out/modules/wrongns/options.nix << 'EOF'
    { lib, ... }: {
      options.bad = {
        enable = lib.mkEnableOption "bad";
      };
    }
    EOF

    # nested/child/options.nix: correctly namespaced under nested.child
    cat > $out/modules/nested/child/options.nix << 'EOF'
    { lib, ... }: {
      options.nested.child = {
        enable = lib.mkEnableOption "child";
      };
    }
    EOF

    # empty/options.nix: guarded module with only auto-injected enable (no user options)
    cat > $out/modules/empty/options.nix << 'EOF'
    { lib, ... }: {
    }
    EOF
  '';

  modulesRoot = testSource + "/modules";

  # Module infos matching the fixture structure
  manualInfos = [
    { path = modulesRoot + "/foo"; modPath = [ "foo" ]; }
    { path = modulesRoot + "/wrongns"; modPath = [ "wrongns" ]; }
    { path = modulesRoot + "/nested/child"; modPath = [ "nested" "child" ]; }
    { path = modulesRoot + "/empty"; modPath = [ "empty" ]; }
  ];

  # ================================================================
  # Test 1: collectOptionLeaves — walks evaluated options tree
  # ================================================================
  # Pass paths directly so module system tracks declaration files
  collectTestEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/options.nix")
      (modulesRoot + "/wrongns/options.nix")
    ];
  };

  collectLeaves = fhs-modules.collectOptionLeaves collectTestEval.options;
  leafLocs = map (leaf: leaf.loc) collectLeaves;

  # ================================================================
  # Test 2: validateOptionNamespaces — identifies violations
  # ================================================================
  validationEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/options.nix")
      (modulesRoot + "/wrongns/options.nix")
      (modulesRoot + "/nested/child/options.nix")
    ];
  };

  violations = fhs-modules.validateOptionNamespaces manualInfos validationEval.options;
  violationLocs = map (v: v.loc) violations;

  # ================================================================
  # Test 3: mkStrictValidationModule — produces assertions
  # ================================================================
  assertionsEval = lib.evalModules {
    modules = [
      (modulesRoot + "/foo/options.nix")
      (modulesRoot + "/wrongns/options.nix")
      (fhs-modules.mkStrictValidationModule manualInfos)
    ];
  };

  allAssertions = assertionsEval.config.assertions or [ ];
  failedAssertions = builtins.filter (a: !a.assertion) allAssertions;

  # ================================================================
  # Test 4: Cross-namespace options are flagged (flake-fhs convention)
  # ================================================================
  crossNsSource = pkgs.runCommand "cross-ns-test" { } ''
    mkdir -p $out/modules/foo
    cat > $out/modules/foo/options.nix << 'EOF'
    { lib, ... }: {
      options.foo.enable = lib.mkEnableOption "foo";
      options.services.integration = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    }
    EOF
  '';

  crossNsInfos = [
    { path = crossNsSource + "/modules/foo"; modPath = [ "foo" ]; }
  ];

  crossNsEval = lib.evalModules {
    modules = [
      (crossNsSource + "/modules/foo/options.nix")
      (fhs-modules.mkStrictValidationModule crossNsInfos)
    ];
  };

  crossNsFailed = builtins.filter (a: !a.assertion) (crossNsEval.config.assertions or [ ]);

  # ================================================================
  # Test 5: strictOptions disabled by default
  # ================================================================
  noStrictOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ modulesRoot ];
    suffix = ".nix";
    strictOptions = false;
  };

  noStrictEval = lib.evalModules {
    modules = [ noStrictOutput.nixosModules.default ];
  };

  noStrictFailed = builtins.filter (a: !a.assertion) (noStrictEval.config.assertions or [ ]);

  # ================================================================
  # Test 6: strictOptions enabled end-to-end via mkModulesOutput
  # ================================================================
  strictOutput = fhs-modules.mkModulesOutput {
    moduleDirs = [ modulesRoot ];
    suffix = ".nix";
    strictOptions = true;
  };

  strictEval = lib.evalModules {
    modules = [ strictOutput.nixosModules.default ];
  };

  strictFailed = builtins.filter (a: !a.assertion) (strictEval.config.assertions or [ ]);

  # ================================================================
  # Compute test results (PASS/FAIL strings, no special chars)
  # ================================================================
  has = loc: locs: builtins.any (l: l == loc) locs;

  checks = {
    # --- Test 1: collectOptionLeaves ---
    t1_count =
      if builtins.length collectLeaves == 4 then "PASS"
      else "FAIL: expected 4 leaves got ${toString (builtins.length collectLeaves)}";
    t1_foo_enable =
      if has [ "foo" "enable" ] leafLocs then "PASS"
      else "FAIL: foo.enable not found";
    t1_foo_setting =
      if has [ "foo" "setting" ] leafLocs then "PASS"
      else "FAIL: foo.setting not found";
    t1_bad_enable =
      if has [ "bad" "enable" ] leafLocs then "PASS"
      else "FAIL: bad.enable not found";

    # --- Test 2: validateOptionNamespaces ---
    t2_foo_ok =
      if !(has [ "foo" "enable" ] violationLocs) && !(has [ "foo" "setting" ] violationLocs) then "PASS"
      else "FAIL: foo should not be in violations";
    t2_nested_ok =
      if !(has [ "nested" "child" "enable" ] violationLocs) then "PASS"
      else "FAIL: nested.child should not be in violations";
    t2_bad_caught =
      if has [ "bad" "enable" ] violationLocs then "PASS"
      else "FAIL: bad.enable should be in violations";
    t2_count =
      if builtins.length violations == 1 then "PASS"
      else "FAIL: expected 1 violation got ${toString (builtins.length violations)}";

    # --- Test 3: mkStrictValidationModule ---
    t3_count =
      if builtins.length failedAssertions == 1 then "PASS"
      else "FAIL: expected 1 failed assertion got ${toString (builtins.length failedAssertions)}";
    t3_message =
      let
        msg = if failedAssertions != [ ] then (builtins.head failedAssertions).message else "";
        mentionsBoth = builtins.match ".*bad.*wrongns.*" msg != null
          || builtins.match ".*wrongns.*bad.*" msg != null;
      in
      if mentionsBoth then "PASS"
      else "FAIL: assertion message does not mention both bad and wrongns";

    # --- Test 4: cross-namespace allowed ---
    t4_cross_flagged =
      if crossNsFailed != [ ] then "PASS"
      else "FAIL: cross-namespace should be flagged";

    # --- Test 5: disabled by default ---
    t5_no_assertions =
      if noStrictFailed == [ ] then "PASS"
      else "FAIL: should have no assertions when disabled";

    # --- Test 6: enabled end-to-end ---
    t6_active =
      if builtins.length strictFailed == 1 then "PASS"
      else "FAIL: expected 1 violation with strictOptions got ${toString (builtins.length strictFailed)}";
  };

  checkValues = builtins.attrValues checks;
  anyFail = builtins.any (v: builtins.match "FAIL.*" v != null) checkValues;

in
pkgs.runCommand "check-strict-options"
  { inherit checkValues; }
  ''
    echo "=== Test 1: collectOptionLeaves ==="
    echo "  ${checks.t1_count}"
    echo "  ${checks.t1_foo_enable}"
    echo "  ${checks.t1_foo_setting}"
    echo "  ${checks.t1_bad_enable}"

    echo ""
    echo "=== Test 2: validateOptionNamespaces ==="
    echo "  ${checks.t2_foo_ok}"
    echo "  ${checks.t2_nested_ok}"
    echo "  ${checks.t2_bad_caught}"
    echo "  ${checks.t2_count}"

    echo ""
    echo "=== Test 3: mkStrictValidationModule ==="
    echo "  ${checks.t3_count}"
    echo "  ${checks.t3_message}"

    echo ""
    echo "=== Test 4: Cross-namespace flagged ==="
    echo "  ${checks.t4_cross_flagged}"

    echo ""
    echo "=== Test 5: Disabled by default ==="
    echo "  ${checks.t5_no_assertions}"

    echo ""
    echo "=== Test 6: Enabled via mkModulesOutput ==="
    echo "  ${checks.t6_active}"

    echo ""
    ${lib.optionalString anyFail "echo '=== SOME TESTS FAILED ==='; exit 1"}

    echo "=== All tests passed ==="
    touch $out
  ''
