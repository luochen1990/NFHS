{
  pkgs,
  self,
  lib,
  ...
}:
{
  scope = lib.mkScope (
    pkgs
    // {
      inherit self lib;
    }
  );
}
