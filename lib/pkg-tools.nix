# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
# :: Context -> Tools
lib: rec {
  # Infer the main program name from a package derivation
  # This mimics the behavior in nixpkgs where mainProgram defaults to pname
  # or the name without version suffix
  #
  # :: Derivation a -> String
  inferMainProgram =
    pkg:
    if pkg ? meta.mainProgram && pkg.meta.mainProgram != null then
      pkg.meta.mainProgram
    else if pkg ? pname && pkg.pname != null then
      pkg.pname
    else
      # Remove version suffix from name (e.g., "hello-2.10" -> "hello")
      # Use builtins.match as fallback since we might not have full lib
      let
        # Try to parse version suffix patterns like "-1.0.0", "_2.3", etc.
        parts = builtins.match "^([^-_]+)[-_]" pkg.name;
      in
      if parts != null then
        builtins.head parts
      else
        # Fallback: just return the name as-is
        pkg.name;

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
