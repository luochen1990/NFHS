{ pkgs, ... }:

pkgs.mkShell {
  packages = [
    pkgs.python3
  ];
}
