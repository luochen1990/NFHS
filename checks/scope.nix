{
  pkgs,
  self,
  lib,
  ...
}:
let
  utils' = lib // (import ../lib/list.nix) // (import ../lib/dict.nix) // (import ../lib/file.nix);
  inherit (import ../lib/fhs-lib.nix utils') prepareLib;
  libWithUtils = utils' // { inherit prepareLib; };
in
{
  scope = lib.mkScope (pkgs // {
    inherit self lib;
    fhs-modules = import ../lib/fhs-modules.nix libWithUtils;
    flake-fhs = import ../lib/flake-fhs.nix libWithUtils;
  });
}
