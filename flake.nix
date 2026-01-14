{
  description = "Test";

  outputs =
    { self, nixpkgs, ... }:
    let

      lib = nixpkgs.lib;
      utils' = lib // (import ./lib/list.nix) // (import ./lib/dict.nix) // (import ./lib/file.nix);
      inherit (import ./lib/prepare-lib.nix utils') prepareLib;
      utils = prepareLib {
        roots = [ ./. ];
        lib = lib;
      };
    in
    utils.mkFlake {
      roots = [ ./. ];
      supportedSystems = [ "x86_64-linux" ];
      inherit self nixpkgs;
      inputs = self.inputs;
    }
    // {
      # Provide lib and mkFlake outputs for backward compatibility with templates
      lib = utils;
      mkFlake = utils.mkFlake;
    };
}
