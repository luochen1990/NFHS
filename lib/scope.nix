lib:
{
  mkScope =
    scope:
    scope
    // {
      callPackage = lib.callPackageWith scope;
    };
}
