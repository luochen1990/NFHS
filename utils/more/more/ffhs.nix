# Flake FHS core implementation
# mkFlake function that auto-generates flake outputs from directory structure

{ lib, pkgs }:

let
  # Import utils preparation system
  utilsSystem = import ../../utils.nix;

in
rec {
  # Main mkFlake function
  mkFlake =
    {
      self,
      lib,
      nixpkgs,
      inputs ? { },
      root ? [ ./. ],
      supportedSystems ? (
        lib.systems.flakeExposed or [
          "x86_64-linux"
          "x86_64-darwin"
          "aarch64-linux"
          "aarch64-darwin"
        ]
      ),
      nixpkgsConfig ? {
        allowUnfree = true;
      },
    }:
    let
      roots = root;

      # Define utils once and reuse throughout
      basicUtils = utilsSystem.prepareUtils ./../../../utils;
      utils = basicUtils.more { inherit lib; };

      inherit (basicUtils)
        unionFor
        dict
        ;

      inherit (basicUtils)
        for
        concatMap
        ;

      # Helper functions
      systemContext' = selfArg: system: rec {
        inherit system inputs;
        pkgs =
          nixpkgs.legacyPackages.${system} or (import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
          });
        tools = utilsSystem.prepareUtils (../../.. + "/utils").more { inherit lib; }.more { inherit pkgs; };
        specialArgs = {
          self = selfArg;
          inherit
            system
            pkgs
            inputs
            tools
            roots
            ;
        };
      };

      eachSystem =
        f:
        dict supportedSystems (
          system:
          let
            context = systemContext' self system;
          in
          f context
        );

      # Updated component discovery that respects multiple roots
      discoverComponents' =
        componentType:
        let
          # Collect components from all roots as a flat list
          allComponents = concatMap (
            root:
            let
              componentPath = root + "/${componentType}";
            in
            if builtins.pathExists componentPath then
              for (utils.lsDirs componentPath) (name: {
                inherit name root;
                path = componentPath + "/${name}";
              })
            else
              [ ]
          ) roots;
        in
        allComponents;

      # Package discovery with optional default.nix control
      buildPackages' =
        context:
        let
          components = discoverComponents' "pkgs";
          # Check if any pkgs/default.nix exists in roots
          hasDefault = builtins.any (root: builtins.pathExists (root + "/pkgs/default.nix")) roots;
        in
        if hasDefault then
          # Use default.nix to control package visibility
          let
            defaultPkgs = concatMap (
              root:
              let
                defaultPath = root + "/pkgs/default.nix";
              in
              if builtins.pathExists defaultPath then
                let
                  result = import defaultPath context;
                in
                if builtins.isAttrs result then [ result ] else [ ]
              else
                [ ]
            ) roots;
          in
          # Merge all package sets from default.nix files
          builtins.foldl' (acc: pkgs: acc // pkgs) { } defaultPkgs
        else
          # Auto-discover all packages
          dict components (
            name:
            { path, ... }:
            {
              "${name}" = context.pkgs.callPackage (path + "/package.nix") { };
            }
          );

    in
    {
      # Generate all flake outputs
      packages = eachSystem (context: buildPackages' context);

      devShells = eachSystem (
        context:
        let
          components = discoverComponents' "shells";
        in
        if components == [ ] then
          { }
        else
          builtins.foldl' (
            acc: comp:
            acc
            // {
              "${comp.name}" = import comp.path context;
            }
          ) { } components
      );

      apps = eachSystem (
        context:
        let
          components = discoverComponents' "apps";
        in
        if components == [ ] then
          { }
        else
          builtins.foldl' (
            acc: comp:
            acc
            // {
              "${comp.name}" = import comp.path context;
            }
          ) { } components
      );

      nixosModules =
        let
          components = discoverComponents' "modules";
        in
        let
          componentList = components;
        in
        builtins.foldl' (
          acc: comp:
          acc
          // {
            "${comp.name}" = import comp.path;
          }
        ) { } componentList
        // {
          default =
            let
              context = systemContext' self "x86_64-linux";
            in
            unionFor components ({ name, path, ... }: import path);
        };

      nixosConfigurations =
        let
          components = discoverComponents' "profiles";
          context = systemContext' self "x86_64-linux";
          modulesList =
            let
              moduleComponents = discoverComponents' "modules";
            in
            builtins.foldl' (
              acc: comp:
              acc
              ++ [
                import
                comp.path
              ]
            ) [ ] moduleComponents;
        in
        let
          profileList = components;
        in
        builtins.foldl' (
          acc: comp:
          acc
          // {
            "${comp.name}" = pkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = context.specialArgs // {
                name = comp.name;
              };
              modules = [ (comp.path + "/configuration.nix") ] ++ modulesList;
            };
          }
        ) { } profileList;

      checks = eachSystem (
        context:
        let
          components = discoverComponents' "checks";
        in
        if components == [ ] then
          { }
        else
          builtins.foldl' (
            acc: comp:
            acc
            // {
              "${comp.name}" = import comp.path context;
            }
          ) { } components
      );

      lib =
        let
          context = systemContext' self "x86_64-linux";
          # Filter out system utils directory to avoid conflicts
          userUtilsComponents = builtins.filter (comp: comp.name != "utils") (discoverComponents' "utils");
        in
        builtins.foldl' (
          acc: comp:
          acc
          // {
            "${comp.name}" = import comp.path context;
          }
        ) { } userUtilsComponents;

      templates =
        let
          readTemplatesFromRoot =
            root:
            let
              templatePath = root + "/templates";
            in
            if builtins.pathExists templatePath then
              for (utils.lsDirs templatePath) (
                name:
                let
                  fullPath = templatePath + "/${name}";
                  flakePath = fullPath + "/flake.nix";
                  hasFlake = builtins.pathExists flakePath;
                  description =
                    if hasFlake then (import flakePath).description or "Template: ${name}" else "Template: ${name}";
                in
                {
                  inherit name;
                  value = {
                    path = fullPath;
                    inherit description;
                  };
                }
              )
            else
              [ ];

          allTemplateLists = map readTemplatesFromRoot roots;
          allTemplates = concatMap (x: x) allTemplateLists;
        in
        builtins.listToAttrs allTemplates;

      # Auto-generated overlay for packages
      overlays.default =
        final: prev:
        let
          utilsSystem = import ../../utils.nix;
          overlayUtils = utilsSystem.prepareUtils ../../...more { lib = final.lib; }.more { pkgs = final; };
          context = {
            pkgs = final;
            inherit (final) lib;
            tools = overlayUtils;
          };
        in
        buildPackages' context;

      # Formatter
      formatter = eachSystem ({ system, pkgs, ... }: pkgs.nixfmt-tree or pkgs.nixfmt);
    };

}
