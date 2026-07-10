# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS core implementation
#
flakeFhsLib:
let
  inherit (builtins)
    tail
    elem
    pathExists
    listToAttrs
    concatLists
    concatStringsSep
    mapAttrs
    ;

  inherit (flakeFhsLib)
    genAttrs
    forFilter
    exploreDir
    ;

  # Core implementation of mkFlake logic
  mkFlakeCore =
    args:
    let
      inherit (args)
        self
        nixpkgs
        inputs
        lib
        supportedSystems
        nixpkgsConfig
        nixpkgsOverlays
        layout
        evalContext
        ;

      partOf = mapAttrs (
        _name: value: x:
        elem x value.subdirs
      ) layout;

      # roots = [Path]

      roots = forFilter layout.roots (
        d:
        let
          p = self.outPath + "/${d}";
        in
        if pathExists p then p else null
      );

      # system related context
      mkEvalContext =
        systemInfo:
        let
          system = systemInfo.system or (lib.head supportedSystems);
          hostNixpkgsConfig =
            nixpkgsConfig // ((systemInfo.nixpkgs or { }).config or systemInfo.nixpkgsConfig or { });
          hostNixpkgsOverlays =
            nixpkgsOverlays ++ ((systemInfo.nixpkgs or { }).overlays or systemInfo.nixpkgsOverlays or [ ]);

          pkgs = (
            import nixpkgs {
              inherit system;
              config = hostNixpkgsConfig;
              overlays = hostNixpkgsOverlays;
            }
          );
          preparedLib = flakeFhsLib.prepareLib {
            inherit roots pkgs;
            libSubdirs = layout.lib.subdirs;
            lib = mergedLib;
          };
          mergedLib = flakeFhsLib // preparedLib // lib; # TODO: configurable
          userCtx = evalContext {
            inherit
              system
              pkgs
              ;
            config = hostNixpkgsConfig;
            overlays = hostNixpkgsOverlays;
          };
          specialArgs = {
            inherit
              self
              system
              inputs
              ;
            lib = mergedLib;
          }
          // (userCtx.specialArgs or { });

          scope = mergedLib.mkScope pkgs;
        in
        {
          inherit
            self
            system
            pkgs
            specialArgs
            inputs
            scope
            ;
          lib = mergedLib;
        }
        // (removeAttrs userCtx [ "specialArgs" ]);

      # Per-system output builder
      # eachSystem : (SystemContext -> a) -> Dict System a
      eachSystem =
        outputBuilder:
        genAttrs supportedSystems (
          system:
          let
            evalContext = mkEvalContext { inherit system; };
          in
          outputBuilder evalContext
        );

      # Discover module directories
      moduleDirs = concatLists (
        map (
          root:
          forFilter layout.nixosModules.subdirs (
            subdir:
            let
              p = root + "/${subdir}";
            in
            if pathExists p then p else null
          )
        ) roots
      );

      # Collect all modules first to check if there are any
      modulesOutput = flakeFhsLib.mkModulesOutput {
        moduleDirs = moduleDirs;
        suffix = layout.nixosModules.suffix;
      };

      # Shared modules for both NixOS configurations and Colmena
      # Only include modules if there are any
      sharedModules = [
        hostnameModule
      ]
      ++ (
        if builtins.hasAttr "default" modulesOutput.nixosModules then
          [ modulesOutput.nixosModules.default ]
        else
          [ ]
      );

      # Inject hostname by default
      hostnameModule =
        { hostname, lib, ... }:
        {
          networking.hostName = lib.mkDefault hostname;
        };

      # Discover hosts
      validHosts = exploreDir roots (it: rec {
        configuration-dot-nix = it.path + "/configuration.nix";
        marked = pathExists configuration-dot-nix;
        into = it.depth == 0 && partOf.nixosConfigurations it.name;
        pick = it.depth >= 1 && marked;

        # Read system info
        default-dot-nix = it.path + "/default.nix";
        hasDefault = pathExists default-dot-nix;
        info = if hasDefault then import default-dot-nix else { system = "x86_64-linux"; };

        out = {
          name = concatStringsSep "/" (tail it.breadcrumbs');
          path = it.path;
          inherit info;
        };
      });

      # ================================================================
      # Formatter & devShells outputs
      # ================================================================

      formatter = (flakeFhsLib.mkFormatterOutput args { inherit eachSystem; }).formatter;

      allProjectDrvs =
        evalContext:
        let
          load = subdir: map (i: i.value) (flakeFhsLib.loadScopedOutputs args roots subdir evalContext);
        in
        load layout.packages.subdirs ++ load layout.apps.subdirs ++ load layout.checks.subdirs;

      devShells =
        (flakeFhsLib.mkShellsOutput args {
          inherit
            roots
            partOf
            eachSystem
            allProjectDrvs
            formatter
            ;
        }).devShells;

    in
    {
      # Generate all flake outputs

      packages = eachSystem (
        evalContext:
        listToAttrs (flakeFhsLib.loadScopedOutputs args roots layout.packages.subdirs evalContext)
      );

      apps = eachSystem (
        evalContext:
        let
          inherit (flakeFhsLib) inferMainProgram;
          rawApps = flakeFhsLib.loadScopedOutputs args roots layout.apps.subdirs evalContext;
        in
        listToAttrs (
          map (app: {
            name = app.name;
            value = {
              type = "app";
              program = "${app.value}/bin/${inferMainProgram app.value}";
            };
          }) rawApps
        )
      );

      checks = eachSystem (
        evalContext: listToAttrs (flakeFhsLib.loadScopedOutputs args roots layout.checks.subdirs evalContext)
      );

      lib = flakeFhsLib.prepareLib {
        inherit roots lib;
        libSubdirs = layout.lib.subdirs;
      };

      inherit formatter devShells;
    }
    // (flakeFhsLib.mkColmenaOutput args {
      inherit validHosts sharedModules mkEvalContext;
    })
    // (flakeFhsLib.mkTemplatesOutput args {
      inherit roots;
    })
    // modulesOutput
    // (flakeFhsLib.mkConfigurationsOutput args {
      inherit validHosts sharedModules mkEvalContext;
    });
in
{
  inherit mkFlakeCore;
}
