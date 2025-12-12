# Test that validates all templates using Python validation
#
# IMPORTANT: This test MUST use local path replacement to validate templates work with the
# current development version of flake-fhs, NOT the GitHub release. We copy the flake-fhs
# source to a local directory within the Nix build environment and test templates against it.
# This ensures we validate the actual logic being developed.
#
# Do NOT modify this to use GitHub URLs or skip local path testing, as that would defeat
# the purpose of validating the current development changes.
{ pkgs, lib, ... }:

pkgs.runCommand "templates-validation" {
  nativeBuildInputs = [ pkgs.python3 pkgs.nix ];
} ''
  set -e
  echo "🧪 Running comprehensive template validation..."

  # Create flake-fhs copy in the build directory (no need for /tmp!)
  FLAKE_FHS_COPY="$PWD/temp-flake-fhs"
  cp -r ${../.} "$FLAKE_FHS_COPY"
  chmod -R u+rw "$FLAKE_FHS_COPY"
  echo "Copied flake-fhs to build directory: $FLAKE_FHS_COPY"

  # Run Python validator with local path to copied flake-fhs
  python3 ${./validators.py} \
    --templates-dir ${../templates} \
    --project-root "$FLAKE_FHS_COPY" \
    --format text

  echo "✅ Template validation completed!"
  touch $out
''