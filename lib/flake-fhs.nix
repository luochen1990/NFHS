# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS core implementation
# mkFlake function that auto-generates flake outputs from directory structure
lib:
let
  flakeFhsLib = lib;
  inherit (builtins)
    pathExists
    listToAttrs
    concatStringsSep
    tail
    concatLists
    elem
    isFunction
    ;

  inherit (lib)
    prepareLib
    unionFor
    dict
    for
    forFilter
    #concat #NOTE: this is 2-nary . e.g. concat a b
    concatFor
    lsDirs
    lsFiles
    findSubDirsContains
    exploreDir
    hasSuffix
    isEmptyFile
    ;

  loadModule = args: m: if isFunction m then m args else m;

  setDefaultModuleLocation =
    if builtins.hasAttr "setDefaultModuleLocation" lib then
      lib.setDefaultModuleLocation
    else if
      builtins.hasAttr "modules" lib && builtins.hasAttr "setDefaultModuleLocation" lib.modules
    then
      lib.modules.setDefaultModuleLocation
    else
      (file: m: m);

  # args: [ { argName = isOptional; ... } ... ]
  # Returns: { argName = isOptional; ... } where isOptional is true only if ALL are true (AND logic).
  # If an arg is mandatory (false) in ANY module, it becomes mandatory (false) in the result.
  mergeFnArgs =
    argsList:
    let
      # Get all unique argument names
      allKeys = lib.unique (concatLists (map builtins.attrNames argsList));
      # Determine if a key should be optional.
      # It is optional (true) ONLY if it is optional in ALL signatures that contain it?
      # Wait.
      # Module A: { foo }: ... (foo mandatory/false)
      # Module B: { foo ? 1 }: ... (foo optional/true)
      # Merged: foo should be mandatory (false), because A needs it.
      # Logic: default to true (optional), AND with specific value.
      # If missing from a module?
      # Module C: { bar }: ... (foo missing)
      # If C doesn't ask for foo, it doesn't care.
      # So we only care about modules that HAVE the key.
      # If A has foo=false, then foo is false.

      mergeKey =
        k:
        let
          # Extract the isOptional value for key k from all args that have it
          vals = lib.catAttrs k argsList;
        in
        # If any module says it's mandatory (false), then it is mandatory.
        # So we want to check if ALL are true.
        lib.all (x: x) vals;
    in
    lib.genAttrs allKeys mergeKey;

  # mkOptionsModule : GuardedTreeNode -> Module
  mkOptionsModule =
    it:
    let
      modPath = it.modPath;
      options-dot-nix = it.path + "/options.nix";
      opts = if (isEmptyFile options-dot-nix) then { } else import options-dot-nix;
      userArgs = if isFunction opts then builtins.functionArgs opts else { };
    in
    lib.setFunctionArgs (
      moduleArgs:
      let
        rawOptions = if isFunction opts then opts moduleArgs else opts;
        virtualEnableOption = lib.mkEnableOption (concatStringsSep "." modPath);
        filledOptions = {
          enable = virtualEnableOption;
        }
        // rawOptions;
      in
      setDefaultModuleLocation options-dot-nix {
        options = lib.attrsets.setAttrByPath modPath filledOptions;
      }
    ) userArgs;

  # mkDefaultModule : GuardedTreeNode -> Module
  mkDefaultModule =
    it:
    let
      # Pre-load modules to inspect signatures
      importedModules = map import it.unguardedConfigPaths;

      # Calculate merged signature
      # If any module requires an arg (mandatory), the wrapper must require it.
      userArgs = mergeFnArgs (
        map (m: if isFunction m then builtins.functionArgs m else { }) importedModules
      );

      # Wrapper must also accept lib and config for its own logic
      wrapperArgs = userArgs // {
        lib = false;
        config = false;
      };

      default-dot-nix = it.path + "/default.nix";
      generated-default-dot-nix = it.path + "/.generated.default.nix";
      location = if pathExists default-dot-nix then default-dot-nix else generated-default-dot-nix;
    in
    setDefaultModuleLocation location (
      lib.setFunctionArgs (
        args@{
          lib,
          config,
          ...
        }:
        {
          config = lib.mkIf (lib.attrsets.getAttrFromPath it.modPath config).enable (
            lib.mkMerge (
              map (
                m:
                let
                  r = loadModule args m;
                in
                r.config or r
              ) importedModules
            )
          );
        }
      ) wrapperArgs
    );

  mkGuardedTree =
    rootModulePaths:
    let
      forest = map (
        path:
        mkGuardedTreeNode {
          inherit path;
          modPath = [ ];
        }
      ) rootModulePaths;
    in
    {
      # TODO: 这里需要去重
      guardedChildrenNodes = concatFor forest (t: t.guardedChildrenNodes);
      unguardedConfigPaths = concatFor forest (t: t.unguardedConfigPaths);
    };

  mkGuardedTreeNode =
    {
      modPath,
      path,
    }:
    let
      unguardedConfigPaths = concatLists (
        exploreDir [ path ] (it: rec {
          options-dot-nix = it.path + "/options.nix";
          default-dot-nix = it.path + "/default.nix";
          guarded = pathExists options-dot-nix;
          defaulted = pathExists default-dot-nix;
          into = !(guarded || defaulted);
          pick = !guarded;
          out =
            if defaulted then
              [ default-dot-nix ]
            else
              forFilter (lsFiles it.path) (
                fname: if hasSuffix ".nix" fname then (it.path + "/${fname}") else null
              );
        })
      );

      guardedChildrenNodes = exploreDir [ path ] (it: rec {
        options-dot-nix = it.path + "/options.nix";
        guarded = pathExists options-dot-nix;
        into = !guarded;
        pick = guarded;
        out = mkGuardedTreeNode {
          modPath = it.breadcrumbs';
          path = it.path;
        };
      });
    in
    {
      inherit
        modPath
        path
        guardedChildrenNodes
        unguardedConfigPaths
        ;
    };

  defaultLayout = {
    roots = {
      subdirs = [
        ""
        "/nix"
      ];
    };
    packages = {
      subdirs = [
        "pkgs"
        "packages"
      ];
    };
    nixosModules = {
      subdirs = [
        "modules"
        "nixosModules"
      ];
    };
    nixosConfigurations = {
      subdirs = [
        "profiles"
        "hosts"
        "nixosConfigurations"
      ];
    };
    devShells = {
      subdirs = [
        "shells"
        "devShells"
      ];
    };
    apps = {
      subdirs = [ "apps" ];
    };
    lib = {
      subdirs = [
        "lib"
        "tools"
        "utils"
      ];
    };
    checks = {
      subdirs = [ "checks" ];
    };
    templates = {
      subdirs = [ "templates" ];
    };
  };

  # Configuration Module Schema
  flakeFhsOptions =
    { lib, ... }:
    let
      mkLayoutEntry =
        description: default:
        lib.mkOption {
          inherit description;
          inherit default;
          type = lib.types.coercedTo (lib.types.listOf lib.types.str) (l: { subdirs = l; }) (
            lib.types.submodule {
              options.subdirs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "List of subdirectories";
                default = [ ];
              };
            }
          );
        };
    in
    {
      options = {
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = lib.systems.flakeExposed;
          description = "List of supported systems";
        };

        nixpkgs.config = lib.mkOption {
          type = lib.types.attrs;
          default = {
            allowUnfree = true;
          };
          description = "Nixpkgs configuration";
        };

        layout = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrs;
            options = {
              roots = mkLayoutEntry "Roots directories" defaultLayout.roots;
              packages = mkLayoutEntry "Packages directories" defaultLayout.packages;
              nixosModules = mkLayoutEntry "NixOS modules directories" defaultLayout.nixosModules;
              nixosConfigurations = mkLayoutEntry "NixOS configurations directories" defaultLayout.nixosConfigurations;
              devShells = mkLayoutEntry "DevShells directories" defaultLayout.devShells;
              apps = mkLayoutEntry "Apps directories" defaultLayout.apps;
              lib = mkLayoutEntry "Lib directories" defaultLayout.lib;
              checks = mkLayoutEntry "Checks directories" defaultLayout.checks;
              templates = mkLayoutEntry "Templates directories" defaultLayout.templates;
            };
          };
          default = { };
          description = "Directory layout configuration";
        };

        flake = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Extra flake outputs to merge with FHS outputs";
        };

        nixosConfigurations = {
          specialArgs = lib.mkOption {
            type = lib.types.functionTo lib.types.attrs;
            default = _: { };
            description = "Extra specialArgs to pass to nixosSystem. Receives system as argument.";
          };

          perHost = {
            specialArgs = lib.mkOption {
              type = lib.types.functionTo lib.types.attrs;
              default = _: { };
              description = "Extra specialArgs to pass to nixosSystem. Receives hostName as argument.";
            };
          };
        };
      };
    };

  # Core implementation of mkFlake logic
  # Original implementation restored
  mkFlakeCore =
    {
      self,
      nixpkgs ? self.inputs.nixpkgs,
      inputs ? self.inputs,
      lib ? nixpkgs.lib, # 这里用户提供的 lib 是不附带自定义工具函数的标准库lib
      supportedSystems ? lib.systems.flakeExposed,
      nixpkgsConfig ? {
        allowUnfree = true;
      },
      layout ? defaultLayout,
      nixosConfigurationsConfig ? { },
      ...
    }:
    let
      partOf = builtins.mapAttrs (
        name: value: x:
        elem x (value.subdirs)
      ) layout;

      roots = forFilter (layout.roots.subdirs or [ ]) (
        d:
        let
          p = self.outPath + d;
        in
        if pathExists p then p else null
      );

      # system related context
      systemContext =
        system:
        let
          pkgs = (
            import nixpkgs {
              inherit system;
              config = nixpkgsConfig;
            }
          );
          preparedLib = prepareLib {
            inherit roots pkgs;
            libSubdirs = layout.lib.subdirs;
            lib = mergedLib;
          };
          mergedLib = flakeFhsLib // preparedLib // lib; # TODO: configurable
          specialArgs = {
            inherit
              self
              system
              inputs
              ;
            lib = mergedLib;
          };
        in
        {
          inherit
            self
            system
            pkgs
            lib
            specialArgs
            ;
        };

      # Per-system output builder
      # eachSystem : (SystemContext -> a) -> Dict System a
      eachSystem =
        outputBuilder:
        dict supportedSystems (
          system:
          let
            context = systemContext system;
          in
          outputBuilder context
        );

      moduleTree = mkGuardedTree (
        concatFor roots (
          root:
          forFilter layout.nixosModules.subdirs (
            subdir:
            let
              p = root + "/${subdir}";
            in
            if pathExists p then p else null
          )
        )
      );
    in
    {
      # Generate all flake outputs

      # outputs:
      #  pkgs/        # subdirs marked by package.nix
      #  modules/     # unguarded & guarded by options.nix
      #  profiles/    # shared & marked by configuration.nix
      #  shells/      # top-level files & subdirs marked by shell.nix
      #  apps/        # top-level files & subdirs marked by default.nix
      #  utils/       # more/ and other .nix files
      #  checks/      # top-level files & subdirs marked by default.nix
      #  templates/   # top-level subdirs marked by templates.nix

      packages = eachSystem (
        # TODO: control package visibility with default.nix
        context:
        listToAttrs (
          exploreDir roots (it: rec {
            package-dot-nix = it.path + "/package.nix";
            into = it.depth == 0 && partOf.packages it.name || it.depth >= 1;
            pick = it.depth >= 1 && pathExists package-dot-nix;
            out = {
              name = concatStringsSep "/" (tail it.breadcrumbs');
              value = context.pkgs.callPackage package-dot-nix { };
            };
          })
        )
      );

      apps = eachSystem (
        context:
        let
          inherit (flakeFhsLib.more context.pkgs) inferMainProgram;
        in
        listToAttrs (
          exploreDir roots (it: rec {
            package-dot-nix = it.path + "/package.nix";
            pkg = context.pkgs.callPackage package-dot-nix { };
            mainProgram = inferMainProgram pkg;
            into = it.depth == 0 && partOf.apps it.name || it.depth >= 1;
            pick = it.depth >= 1 && pathExists package-dot-nix;
            out = {
              name = concatStringsSep "/" (tail it.breadcrumbs');
              value = {
                type = "app";
                program = "${pkg}/bin/${mainProgram}";
              };
            };
          })
        )
      );

      devShells = eachSystem (
        context:
        listToAttrs (
          concatLists (
            exploreDir roots (it: rec {
              isShellsRoot = it.depth == 0 && partOf.devShells it.name;
              isShellsSubDir = it.depth >= 1;

              into = isShellsRoot || isShellsSubDir;

              out =
                if isShellsRoot then
                  # Case 1: shells/*.nix -> devShells.*
                  forFilter (lsFiles it.path) (
                    fname:
                    if hasSuffix ".nix" fname then
                      {
                        name = lib.removeSuffix ".nix" fname;
                        value = import (it.path + "/${fname}") context;
                      }
                    else
                      null
                  )
                else if isShellsSubDir && pathExists (it.path + "/default.nix") then
                  # Case 2: shells/<name>/default.nix -> devShells.<name>
                  [
                    {
                      name = concatStringsSep "/" (tail it.breadcrumbs');
                      value = import (it.path + "/default.nix") context;
                    }
                  ]
                else
                  [ ];

              pick = out != [ ];
            })
          )
        )
      );

      nixosModules =
        listToAttrs (
          concatFor moduleTree.guardedChildrenNodes (it: [
            {
              name = (concatStringsSep "." it.modPath) + ".options";
              value = (mkOptionsModule it);
            }
            {
              name = (concatStringsSep "." it.modPath) + ".config";
              value = mkDefaultModule it;
            }
          ])
        )
        // {
          default = {
            imports = moduleTree.unguardedConfigPaths;
          };
        };

      nixosConfigurations =
        let
          mkProfile =
            it:
            let
              default-dot-nix = it.path + "/default.nix";
              hasDefault = pathExists default-dot-nix;
              info = if hasDefault then import default-dot-nix else { system = "x86_64-linux"; };
              context = systemContext info.system;
              modules = [
                (it.path + "/configuration.nix")
              ]
              ++ moduleTree.unguardedConfigPaths
              ++ concatFor moduleTree.guardedChildrenNodes (it: [
                # Options module (always imported)
                (mkOptionsModule it)
                # Config module (guarded by enable option)
                (mkDefaultModule it)
              ]);
              # TODO: partial load
              # config = lib.evalModules {
              #   modules = [ ];
              #   specialArgs = { };
              #   args = { };
              #   check = true;
              # };
              hostName = concatStringsSep "/" (tail it.breadcrumbs');
            in
            lib.nixosSystem {
              #lib.nixosSystem {
              inherit (context)
                #self
                system
                #pkgs
                lib
                ;
              specialArgs =
                context.specialArgs
                // nixosConfigurationsConfig.specialArgs info.system
                // nixosConfigurationsConfig.perHost.specialArgs hostName;
              modules = modules ++ [
                #nixpkgs.nixosModules.readOnlyPkgs #TODO: fix this
                { nixpkgs.pkgs = context.pkgs; }
              ];
            };
        in
        listToAttrs (
          exploreDir roots (it: rec {
            configuration-dot-nix = it.path + "/configuration.nix";
            marked = pathExists configuration-dot-nix;
            into = it.depth == 0 && partOf.nixosConfigurations it.name;
            pick = it.depth >= 1 && marked;
            out = {
              name = concatStringsSep "/" (tail it.breadcrumbs');
              value = mkProfile it;
            };
          })
        );

      checks = eachSystem (
        context:
        let
          # 1. File mode: collect top-level .nix files
          fileChecks = concatFor roots (
            root:
            let
              checksPath = root + "/checks";
            in
            if pathExists checksPath then
              for (lsFiles checksPath) (
                name:
                let
                  checkPath = checksPath + "/${name}";
                in
                if builtins.match ".*\\.nix$" name != null && name != "default.nix" then
                  {
                    name = builtins.substring 0 (builtins.stringLength name - 4) name;
                    path = checkPath;
                  }
                else
                  null
              )
            else
              [ ]
          );

          validFileChecks = builtins.filter (x: x != null) fileChecks;

          # 2. Directory mode: recursively find all directories containing default.nix
          directoryChecks = concatFor roots (
            root:
            let
              checksPath = root + "/checks";
            in
            if pathExists checksPath then
              for (findSubDirsContains checksPath "default.nix") (relativePath: {
                name = relativePath;
                path = checksPath + "/${relativePath}";
              })
            else
              [ ]
          );

          # 3. File mode takes precedence over directory mode on name conflicts
          allChecks =
            let
              fileNames = map (item: item.name) validFileChecks;
            in
            validFileChecks ++ builtins.filter (dir: !(builtins.elem dir.name fileNames)) directoryChecks;
        in
        builtins.listToAttrs (
          map (item: {
            name = item.name;
            value = import item.path context;
          }) allChecks
        )
      );

      lib = prepareLib {
        inherit roots lib;
        libSubdirs = layout.lib.subdirs;
      };

      templates =
        let
          readTemplatesFromRoot =
            root:
            let
              templatePath = root + "/templates";
            in
            if pathExists templatePath then
              for (lsDirs templatePath) (
                name:
                let
                  fullPath = templatePath + "/${name}";
                  flakePath = fullPath + "/flake.nix";
                  hasFlake = pathExists flakePath;
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
          allTemplates = concatLists allTemplateLists;
        in
        builtins.listToAttrs allTemplates;

      # Formatter
      formatter = eachSystem (
        { pkgs, ... }:
        let
          treefmtNix = self.outPath + "/treefmt.nix";
          treefmtToml = self.outPath + "/treefmt.toml";
        in
        if pathExists treefmtNix then
          if (inputs ? treefmt-nix) then
            (inputs.treefmt-nix.lib.evalModule pkgs treefmtNix).config.build.wrapper
          else
            #NOTE: the treefmt.nix format is different here
            #DOC: https://nixos.org/manual/nixpkgs/stable/#opt-treefmt-settings
            pkgs.treefmt.withConfig { settings = (import treefmtNix); }
        else if pathExists treefmtToml then
          pkgs.treefmt.withConfig { configFile = treefmtToml; }
        else
          pkgs.treefmt
      );
    };
in
{
  # Main mkFlake function
  mkFlake =
    {
      self ? inputs.self,
      inputs ? self.inputs,
      nixpkgs ? inputs.nixpkgs,
      lib ? nixpkgs.lib, # 这里用户提供的 lib 是不附带自定义工具函数的标准库lib
    }:
    module:
    let
      # Evaluate config module
      eval = lib.evalModules {
        modules = [
          flakeFhsOptions
          module
        ];
        specialArgs = { inherit lib; };
      };

      config = eval.config;

      # 1. Extract and map options to mkFlakeCore args
      fhsFlake = mkFlakeCore {
        inherit
          inputs
          self
          nixpkgs
          lib
          ;

        supportedSystems = config.systems;
        nixpkgsConfig = config.nixpkgs.config;
        layout = config.layout;
        nixosConfigurationsConfig = config.nixosConfigurations;
      };
    in
    lib.recursiveUpdate fhsFlake config.flake;
}
