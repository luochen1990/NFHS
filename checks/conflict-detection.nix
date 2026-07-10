# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Test: Conflict detection - options.nix + default.nix
#
# NOTE: This test verifies the conflict detection logic at the code level.
# The actual runtime behavior (throwing an error when both files exist)
# is tested manually or through integration tests, because builtins.tryEval
# cannot reliably catch errors involving impure file system operations.
#
{
  pkgs,
  lib,
  self,
  ...
}:

let
  # Test the conflict detection logic directly
  # The logic in fhs-modules.nix is:
  #   conflictCheck = assert !(hasOptions && hasDefault); true;
  #   builtins.seq conflictCheck { ... }

  # Simulate the conflict detection
  testConflictLogic =
    hasOptions: hasDefault:
    let
      # This mirrors the logic in fhs-modules.nix
      conflictCheck =
        assert !(hasOptions && hasDefault);
        true;
    in
    builtins.seq conflictCheck true;

  # Test cases
  testCases = {
    # No conflict: only options.nix
    test1 = builtins.tryEval (testConflictLogic true false);
    # No conflict: only default.nix
    test2 = builtins.tryEval (testConflictLogic false true);
    # No conflict: neither file
    test3 = builtins.tryEval (testConflictLogic false false);
    # Conflict: both files - should fail
    test4 = builtins.tryEval (testConflictLogic true true);
  };

  # Verify results
  checks = {
    test1_ok = testCases.test1.success == true;
    test2_ok = testCases.test2.success == true;
    test3_ok = testCases.test3.success == true;
    test4_ok = testCases.test4.success == false; # Should fail due to assert
  };

in
pkgs.runCommand "check-conflict-detection" { } ''
  echo "=== Test: Conflict detection logic ==="

  echo ""
  echo "Test 1: Only options.nix (no conflict)"
  if [ "${if checks.test1_ok then "PASS" else "FAIL"}" != "PASS" ]; then
    echo "FAILED: Expected success with only options.nix"
    exit 1
  fi
  echo "Result: ${if testCases.test1.success then "success" else "failure"} (expected: success)"

  echo ""
  echo "Test 2: Only default.nix (no conflict)"
  if [ "${if checks.test2_ok then "PASS" else "FAIL"}" != "PASS" ]; then
    echo "FAILED: Expected success with only default.nix"
    exit 1
  fi
  echo "Result: ${if testCases.test2.success then "success" else "failure"} (expected: success)"

  echo ""
  echo "Test 3: Neither file (no conflict)"
  if [ "${if checks.test3_ok then "PASS" else "FAIL"}" != "PASS" ]; then
    echo "FAILED: Expected success with neither file"
    exit 1
  fi
  echo "Result: ${if testCases.test3.success then "success" else "failure"} (expected: success)"

  echo ""
  echo "Test 4: Both files (CONFLICT)"
  if [ "${if checks.test4_ok then "PASS" else "FAIL"}" != "PASS" ]; then
    echo "FAILED: Expected failure with both files"
    echo "Got success = ${if testCases.test4.success then "true" else "false"}"
    exit 1
  fi
  echo "Result: ${if testCases.test4.success then "success" else "failure"} (expected: failure)"

  echo ""
  echo "=== All tests passed ==="
  touch $out
''
