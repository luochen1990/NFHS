{ pkgs, ... }:

pkgs.mkShell {
  packages = [
    pkgs.python3
    pkgs.nixfmt
  ];
}
