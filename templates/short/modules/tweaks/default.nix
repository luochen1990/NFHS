{ lib, ... }:

{
  # Manually define enable (flake-fhs would auto-inject it if omitted)
  options.tweaks.enable = lib.mkEnableOption "system tweaks";
}
