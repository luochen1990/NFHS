{
  stdenv,
  writeShellScriptBin,
  lib,
}:

writeShellScriptBin "fortune-fhs" ''
  set -euo pipefail

  fortunes=(
    "Nix FHS makes Nix development easier!"
    "Convention over configuration is the way to go."
    "Zero boilerplate, maximum productivity."
    "Your Nix flakes will never be the same."
    "Structured directories, structured mind."
  )

  random_fortune="''${fortunes[$RANDOM % ''${#fortunes[@]}]}"
  echo "🔮 Flake Fortune: $random_fortune"
''
