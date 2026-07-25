# default devShell: Nix 代码静态检查工具链 (deadnix + statix + nixfmt)
{ pkgs, ... }:
pkgs.mkShell {
  packages = [
    pkgs.just
    pkgs.nixfmt
    pkgs.deadnix
    pkgs.statix
  ];
}
