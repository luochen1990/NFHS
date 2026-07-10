# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
# :: Context -> Tools
lib: rec {
  # Infer the main program name from a package derivation
  # Mirrors the fallback chain in the Nix CLI (src/nix/app.cc toApp):
  #   1. meta.mainProgram  2. pname  3. parseDrvName(name).name
  # Steps 2-3 are delegated to lib.getName to stay aligned with nixpkgs.
  #
  # :: Derivation a -> String
  inferMainProgram =
    pkg:
    if pkg ? meta.mainProgram && pkg.meta.mainProgram != null then
      pkg.meta.mainProgram
    else
      lib.getName pkg;

  # callPackage with custom warnings for deprecated patterns
  #
  # :: Scope -> (Path | Function) -> Attrs -> Derivation
  callPackageWithWarning =
    scope: target: args:
    let
      # Check for 'system' argument in the function
      fn = if builtins.isPath target || builtins.isString target then import target else target;
      requestsSystem = builtins.isFunction fn && (builtins.functionArgs fn) ? system;
      systemProvided = args ? system;

      pathStr =
        if builtins.isPath target || builtins.isString target then toString target else "<unknown>";
      msg = "Warning: File '${pathStr}' requests 'system' argument which may trigger a Nixpkgs warning. Use 'pkgs.stdenv.hostPlatform.system' instead.";
    in
    if requestsSystem && !systemProvided then
      builtins.trace msg (lib.callPackageWith scope target args)
    else
      lib.callPackageWith scope target args;

  # Create a scope (package set) with callPackage
  #
  # :: Scope -> Scope
  mkScope =
    scope:
    assert lib.assertMsg (!builtins.isFunction scope)
      "mkScope: scope must be an attrset, not a function (got ${builtins.typeOf scope})";
    scope
    // {
      callPackage = callPackageWithWarning scope;
    };
}
