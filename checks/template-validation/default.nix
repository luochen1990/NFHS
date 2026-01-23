{
  self,
  pkgs,
  lib,
  ...
}:

let
  # Replicate library setup from flake.nix to ensure flake-fhs.nix has all dependencies
  utils' =
    lib // (import ../../lib/list.nix) // (import ../../lib/dict.nix) // (import ../../lib/file.nix);
  inherit (import ../../lib/prepare-lib.nix utils') prepareLib;

  libWithUtils = utils' // {
    inherit prepareLib;
  };

  # Import the core library we are testing
  flake-fhs = import ../../lib/flake-fhs.nix libWithUtils;

  # Helper to evaluate a single template
  checkTemplate =
    templateName:
    let
      templatePath = ../../templates + "/${templateName}";
      _ = builtins.trace "CheckTemplate: ${templateName} path: ${toString templatePath}" null;

      # Load flake.nix as an expression
      flakeNix = import (templatePath + "/flake.nix");
      # Read flake.nix as text for static checks
      flakeContent = builtins.readFile (templatePath + "/flake.nix");

      # 1. Static Checks
      # Ensure the template uses the correct upstream URL
      urlCheck =
        if builtins.match ".*github:luochen1990/flake-fhs.*" flakeContent != null then
          pkgs.writeText "check-url-${templateName}" "pass"
        else
          throw "Template ${templateName} flake.nix does not contain correct GitHub URL";

      # 2. Mock Inputs & Evaluate
      # We simulate the inputs that would be passed to the flake's outputs function
      mockInputs = {
        self = {
          outPath = templatePath;
          inputs = { };
        };
        # Use the nixpkgs version from the checking environment to avoid fetching
        # We wrap it in an attrset with outPath so it works for both 'import nixpkgs' and 'nixpkgs.lib'
        nixpkgs = {
          outPath = pkgs.path;
          lib = pkgs.lib // {
            nixosSystem = args: import (pkgs.path + "/nixos/lib/eval-config.nix") args;
          };
        };
        # Inject the local lib/flake-fhs.nix to test current changes
        flake-fhs = {
          lib = flake-fhs;
        };
      };

      outputs = flakeNix.outputs mockInputs;
      system = pkgs.stdenv.hostPlatform.system;

      # Extract outputs for the current system
      packages = outputs.packages.${system} or { };
      apps = outputs.apps.${system} or { };
      devShells = outputs.devShells.${system} or { };
      checks = outputs.checks.${system} or { };
      nixosConfigurations = outputs.nixosConfigurations or { };

      # Helper to get derivation or path
      getDrv =
        name: item:
        if lib.isDerivation item then
          item
        else if builtins.isPath item || builtins.isString item then
          item
        else
          throw "Item '${name}' in template ${templateName} is not a derivation or path: ${
            builtins.toJSON (if builtins.isAttrs item then builtins.attrNames item else item)
          }";

      # Validate apps structure
      validateApps =
        let
          validateApp =
            name: app:
            if app ? type && app.type == "app" && app ? program then
              pkgs.writeText "check-app-${templateName}-${name}" "pass"
            else
              throw "Template ${templateName} app ${name} has invalid structure";
        in
        lib.mapAttrsToList validateApp apps;

    in
    [ urlCheck ]
    ++ (lib.mapAttrsToList getDrv packages)
    ++ validateApps
    ++
      # We check that devShells evaluate and can produce their wrapper derivation
      (lib.mapAttrsToList getDrv devShells)
    ++ [
      # Explicit check for devShells presence in std template
      (
        if templateName == "std" && devShells == { } then
          throw "Template ${templateName} should have devShells but found none"
        else
          pkgs.writeText "check-devShells-presence-${templateName}" "pass"
      )
    ]
    ++ (lib.mapAttrsToList getDrv checks)
    ++
      # For NixOS configs, we force evaluation of the toplevel derivation path
      # This catches evaluation errors without requiring a full system build
      (lib.mapAttrsToList (
        name: cfg:
        pkgs.writeText "check-config-${templateName}-${name}" (
          if cfg ? config.system.build.toplevel.drvPath then
            cfg.config.system.build.toplevel.drvPath
          else
            throw "Template ${templateName} config ${name} missing toplevel derivation"
        )
      ) nixosConfigurations);

  # Get list of templates dynamically
  templatesDir = ../../templates;
  files = builtins.readDir templatesDir;
  # Filter for directories not starting with dot
  templateNames = builtins.filter (name: files.${name} == "directory" && !lib.hasPrefix "." name) (
    builtins.attrNames files
  );

  # Aggregate all checks from all templates
  allChecks = lib.flatten (map checkTemplate templateNames);

in
# Create a linkFarm that depends on all checks passing/building
pkgs.linkFarm "template-validation" (
  map (drv: {
    name = if drv ? name then drv.name else builtins.baseNameOf drv;
    path = drv;
  }) allChecks
)
