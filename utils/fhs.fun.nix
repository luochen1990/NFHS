# Flake FHS core implementation
# mkFlake function that auto-generates flake outputs from directory structure

{
  # Import other tool functions
  utils',
  lib,
  nixpkgs,
  inputs ? {}
}:

let
  inherit (utils')
    for
    unionFor
    dict
    findFilesRec
    hasPostfix
    subDirsRec
    isNotHidden
    lsDirs
    lsFiles
    ;

  # System context helper
  systemContext = selfArg: system: rec {
    inherit system;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    tools = utils' // utils'.useLib lib;
    specialArgs = {
      self = selfArg;
      inherit
        system
        pkgs
        inputs
        tools
        ;
    };
  };

  # Helper to process multiple root directories
  eachSystem' = supportedSystems: selfArg: f: dict supportedSystems (system: f (systemContext selfArg system));
  eachSystem = eachSystem' (lib.systems.flakeExposed or [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ]);

  # Discover components from multiple root directories
  discoverComponents = roots: componentType:
    unionFor roots (root:
      let
        componentPath = root + "/${componentType}";
      in
      if builtins.pathExists componentPath then
        for (lsDirs componentPath) (name: {
          inherit name root;
          path = componentPath + "/${name}";
        })
      else
        []
    );

in
rec {
  # Main mkFlake function
  mkFlake = args:
    let
      roots = args.root or [ ./. ];
      supportedSystems = args.supportedSystems or (lib.systems.flakeExposed or [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ]);
      nixpkgsConfig = args.nixpkgsConfig or { allowUnfree = true; };

      # Override systemContext with custom config
      systemContext' = selfArg: system: rec {
        inherit system;
        pkgs = import nixpkgs {
          inherit system;
          config = nixpkgsConfig;
        };
        tools = utils' // utils'.useLib lib;
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

      eachSystem' = supportedSystems: selfArg: f: dict supportedSystems (system: f (systemContext' selfArg system));
      eachSystem = eachSystem' supportedSystems args.self;

      # Updated component discovery that respects multiple roots
      discoverComponents' = componentType:
        unionFor roots (root:
          let
            componentPath = root + "/${componentType}";
          in
          if builtins.pathExists componentPath then
            for (lsDirs componentPath) (name: {
              inherit name root;
              path = componentPath + "/${name}";
            })
          else
            []
        );

      # Package discovery with optional default.nix control
      buildPackages' = context:
        let
          components = discoverComponents' "pkgs";
          # Check if any pkgs/default.nix exists in roots
          defaultPkgs = unionFor roots (root:
            let
              defaultPath = root + "/pkgs/default.nix";
            in
            if builtins.pathExists defaultPath then [ (import defaultPath context) ] else []
          );
        in
        if defaultPkgs != [] then
          # Use default.nix to control package visibility
          builtins.foldl' (acc: pkgs: acc // pkgs) {} defaultPkgs
        else
          # Auto-discover all packages
          unionFor components (
            { name, path, ... }:
            {
              "${name}" = context.pkgs.callPackage (path + "/package.nix") { };
            }
          );

    in
    {
      # Generate all flake outputs
      packages = eachSystem (
        context:
        buildPackages' context
      );

      devShells = eachSystem (
        context:
        let
          components = discoverComponents' "shells";
        in
        unionFor components (
          { name, path, ... }:
          {
            "${name}" = import path context;
          }
        )
      );

      apps = eachSystem (
        context:
        let
          components = discoverComponents' "apps";
        in
        unionFor components (
          { name, path, ... }:
          {
            "${name}" = import path context;
          }
        )
      );

      nixosModules =
        let
          components = discoverComponents' "modules";
        in
        unionFor components (
          { name, path, ... }:
          {
            "${name}" = import path;
          }
        )
        // {
          default =
            let
              context = systemContext' args.self "x86_64-linux";
            in
            unionFor components (
              { name, path, ... }:
              import path
            );
        };

      nixosConfigurations =
        let
          components = discoverComponents' "profiles";
          context = systemContext' args.self "x86_64-linux";
          modulesList = unionFor (discoverComponents' "modules") (
            { name, path, ... }:
            import path
          );
        in
        unionFor components (
          { name, path, ... }:
          {
            "${name}" = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = context.specialArgs // { inherit name; };
              modules = [ (path + "/configuration.nix") ] ++ modulesList;
            };
          }
        );

      checks = eachSystem (
        context:
        let
          components = discoverComponents' "checks";
        in
        unionFor components (
          { name, path, ... }:
          {
            "${name}" = import path context;
          }
        )
      );

      lib =
        let
          context = systemContext' args.self "x86_64-linux";
        in
        unionFor (discoverComponents' "lib") (
          { name, path, ... }:
          {
            "${name}" = import path context;
          }
        );

      templates =
        unionFor (discoverComponents' "templates") (
          { name, path, ... }:
          {
            "${name}" = {
              path = path;
              description = "Template: ${name}";
            };
          }
        );

      # Auto-generated overlay for packages
      overlays.default = final: prev:
        let
          context = { pkgs = final; inherit (final) lib; tools = utils' // utils'.useLib final.lib; };
        in
        buildPackages' context;

      # Formatter
      formatter = eachSystem (
        { system, pkgs, ... }:
        pkgs.nixfmt-tree or pkgs.nixfmt
      );
    };

  # Helper functions
  inherit discoverComponents systemContext eachSystem;
}