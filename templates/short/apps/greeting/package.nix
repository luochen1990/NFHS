{
  lib,
  writeShellScriptBin,
}:

writeShellScriptBin "greeting-app" ''
  #!${writeShellScriptBin}
  echo "Hello from Nix FHS!"
  echo "This app was automatically discovered and packaged."
  echo "Current time: $(date)"
''
// {
  meta.mainProgram = "greeting-app";
  meta.description = "A simple greeting application";
}
