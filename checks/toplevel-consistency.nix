{
  pkgs,
  lib,
  self,
  flake-fhs,
  ...
}:

let
  # Create a dummy flake source with a minimal NixOS configuration
  dummySource = pkgs.runCommand "dummy-source" { } ''
    mkdir -p $out/nixosConfigurations/test-host
    mkdir -p $out/nixosModules

    # Force version info to be consistent across both environments
    cat > $out/nixosModules/force-version.nix <<EOF
    { lib, pkgs, ... }: {
      system.nixos.versionSuffix = lib.mkForce "test";
      system.nixos.revision = lib.mkForce "test-rev";
      # Ensure nixosConfigurations matches Colmena (which gets this from shim)
      nixpkgs.flake.source = lib.mkForce "${toString pkgs.path}";
    }
    EOF

    cat > $out/nixosConfigurations/test-host/configuration.nix <<EOF
    { pkgs, ... }: {
      imports = [ ../../nixosModules/force-version.nix ];
      boot.isContainer = true;
      system.stateVersion = "23.11";
      nixpkgs.hostPlatform = "${pkgs.stdenv.hostPlatform.system}";
      documentation.enable = false;
    }
    EOF
  '';

  # Mock Colmena library
  mockColmena = {
    lib = {
      makeHive = hive: {
        nodes = lib.mapAttrs (
          name: module:
          let
            # We define a dummy deployment option to avoid evaluation errors
            deploymentOption =
              { lib, ... }:
              {
                options.deployment = lib.mkOption {
                  type = lib.types.attrs;
                  default = { };
                };
              };

            evaluated = lib.nixosSystem {
              system = hive.meta.nodeNixpkgs.${name}.stdenv.hostPlatform.system;
              pkgs = hive.meta.nodeNixpkgs.${name};
              specialArgs = hive.meta.nodeSpecialArgs.${name};
              modules = [
                module
                deploymentOption
              ];
            };
          in
          evaluated
        ) (removeAttrs hive [ "meta" ]);
      };
    };
  };

  # Instantiate the flake
  testFlake =
    flake-fhs.mkFlake
      {
        # Mock self to point to our dummy source so validHosts can find configuration.nix
        self = {
          outPath = dummySource;
        };
        inputs = {
          inherit self;
          nixpkgs = {
            outPath = toString pkgs.path;
            lib = pkgs.lib // {
              nixosSystem = args: import (pkgs.path + "/nixos/lib/eval-config.nix") args;
            };
            rev = "0000000000000000000000000000000000000000";
          };
          colmena = mockColmena;
        };
      }
      {
        colmena.enable = true;
      };

  nixosToplevel = testFlake.nixosConfigurations.test-host.config.system.build.toplevel.outPath;
  colmenaToplevel = testFlake.colmenaHive.nodes.test-host.config.system.build.toplevel.outPath;

in
pkgs.runCommand "check-toplevel-consistency" { } ''
  echo "Checking consistency between NixOS and Colmena outputs..."
  echo "NixOS Toplevel:   ${nixosToplevel}"
  echo "Colmena Toplevel: ${colmenaToplevel}"

  if [ "${nixosToplevel}" != "${colmenaToplevel}" ]; then
    echo "FAILED: Paths differ!"
    exit 1
  fi

  touch $out
''
