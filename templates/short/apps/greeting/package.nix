{
  lib,
  writeShellScriptBin,
}:

writeShellScriptBin "greeting-app" ''
  echo "Hello from Nix FHS!"
  echo "This app was automatically discovered and packaged."
  echo "Current time: $(date)"
''
// {
  meta.description = "A simple greeting application";
}
