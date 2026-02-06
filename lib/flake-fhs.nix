# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS core implementation
# mkFlake function that auto-generates flake outputs from directory structure
lib:
let
  # ================================================================
  # Imports & Aliases
  # ================================================================
  flakeFhsLib = lib;
  inherit (builtins)
    pathExists
    listToAttrs
    concatStringsSep
    tail
    concatLists
    concatMap
    elem
    head
    hasAttr
    ;

  inherit (lib)
    prepareLib
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

  # ================================================================
  # Module System Helpers
  # ================================================================
  # warpModule :: [String] -> (Path | Module) -> Module
  warpModule =
    optionsMode: modPath: module:
    let
      isPath = builtins.isPath module || builtins.isString module;
      file = if isPath then module else null;
      raw = if isPath then if isEmptyFile module then { } else import module else module;

      # Check logic for Strict mode
      checkStrict =
        opts: path:
        if opts == { } || path == [ ] then
          true
        else
          let
            h = head path;
          in
          if hasAttr h opts && removeAttrs opts [ h ] == { } then
            checkStrict opts.${h} (tail path)
          else
            false;

      # Core logic to transform module content
      transform =
        content:
        {
          config,
          lib,
          ...
        }:
        let
          opts = content.options or { };

          # 1. Validation
          _ =
            if optionsMode == "strict" && !checkStrict opts modPath then
              throw "Strict mode violation: options in ${toString file} must strictly follow the directory structure ${concatStringsSep "." modPath}"
            else
              null;

          # 2. Nesting
          nestedOpts = if optionsMode == "auto" && opts != { } then lib.setAttrByPath modPath opts else opts;

          # 3. Enable Option
          enablePath = modPath ++ [ "enable" ];
          finalOpts =
            if
              file != null
              && baseNameOf (toString file) == "options.nix"
              && !lib.hasAttrByPath enablePath nestedOpts
            then
              lib.recursiveUpdate nestedOpts (
                lib.setAttrByPath modPath {
                  enable = lib.mkEnableOption (concatStringsSep "." modPath);
                }
              )
            else
              nestedOpts;

          # 4. Config
          explicitConfig = content.config or { };
          implicitConfig = removeAttrs content [
            "imports"
            "options"
            "config"
            "_file"
            "meta"
            "disabledModules"
            "__functor"
            "__functionArgs"
          ];
          mergedConfig = explicitConfig // implicitConfig;
        in
        {
          imports = content.imports or [ ];
          options = finalOpts;
          config = lib.mkIf (lib.attrsets.getAttrFromPath enablePath config) mergedConfig;
        };

      # Wrap raw module into a functor
      functor =
        if builtins.isFunction raw then
          {
            __functor = self: args: transform (raw args) args;
            __functionArgs = builtins.functionArgs raw;
          }
        else
          {
            __functor = self: args: transform raw args;
          };
    in
    if file != null then
      {
        _file = file;
        imports = [ functor ];
      }
    else
      functor;

  # mkOptionsModule : GuardedTreeNode -> Module
  mkOptionsModule =
    optionsMode: it:
    let
      modPath = it.modPath;
      options-dot-nix = it.path + "/options.nix";
    in
    {
      imports = [
        (warpModule optionsMode modPath options-dot-nix)
      ];
    };

  # mkDefaultModule : GuardedTreeNode -> Module
  mkDefaultModule = optionsMode: it: {
    imports = map (warpModule optionsMode it.modPath) it.unguardedConfigPaths;
  };

  # ================================================================
  # Tree Traversal (Guarded)
  # ================================================================
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

  # ================================================================
  # Tree Traversal (Scoped)
  # ================================================================
  mkScopedTreeNode =
    {
      path,
      breadcrumbs,
    }:
    let
      # 1. File Packages: *.nix files in current dir (excluding special ones)
      filePackages = forFilter (lsFiles path) (
        fname:
        if
          hasSuffix ".nix" fname && fname != "scope.nix" && fname != "default.nix" && fname != "package.nix"
        then
          {
            name = lib.removeSuffix ".nix" fname;
            path = path + "/${fname}";
          }
        else
          null
      );

      # 2. Directory Packages & Sub-scopes
      children = exploreDir [ path ] (it: rec {
        scopePath = it.path + "/scope.nix";
        packagePath = it.path + "/package.nix";
        hasScope = pathExists scopePath;
        hasPackage = pathExists packagePath;

        # We pick this node if it has scope or package.
        isInteresting = hasScope || hasPackage;
        pick = isInteresting;

        # Stop recursion if we hit a package boundary.
        into = !hasPackage;

        out = mkScopedTreeNode {
          path = it.path;
          breadcrumbs = breadcrumbs ++ it.breadcrumbs';
        };
      });
    in
    {
      inherit path breadcrumbs;
      hasScope = pathExists (path + "/scope.nix");
      hasPackage = pathExists (path + "/package.nix");
      inherit filePackages children;
    };

  evalScopedTree =
    context: currentScope: currentArgs: node:
    let
      # 1. Determine Scope & Args
      scopePath = node.path + "/scope.nix";

      # Calculate next
      scopedData = if node.hasScope then (import scopePath) context else { };

      # Scope: Inherit (default) or Replace (if provided)
      baseScope = currentScope;
      nextScope = scopedData.scope or baseScope;

      # Args: Inherit & Merge
      baseArgs = currentArgs;
      extraArgs = scopedData.args or { };
      nextArgs = baseArgs // extraArgs;

      # 2. Evaluate Packages

      # 2.1 Directory Package (package.nix)
      dirPkg =
        if node.hasPackage then
          [
            {
              name = concatStringsSep "/" node.breadcrumbs;
              # Pass accumulated args as the second argument to callPackage
              value = nextScope.callPackage (node.path + "/package.nix") nextArgs;
            }
          ]
        else
          [ ];

      # 2.2 File Packages (*.nix)
      filePkgs = map (p: {
        name = concatStringsSep "/" (node.breadcrumbs ++ [ p.name ]);
        value = nextScope.callPackage p.path nextArgs;
      }) node.filePackages;

      currentPkgs = dirPkg ++ filePkgs;

      # 3. Recurse
      childrenPkgs = concatMap (evalScopedTree context nextScope nextArgs) node.children;
    in
    currentPkgs ++ childrenPkgs;

  # ================================================================
  # Configuration Schema
  # ================================================================
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
        "hosts"
        "profiles"
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
          type =
            lib.types.coercedTo (lib.types.listOf (lib.types.either lib.types.str lib.types.path))
              (l: { subdirs = l; })
              (
                lib.types.submodule {
                  options.subdirs = lib.mkOption {
                    type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);
                    description = "List of subdirectories or paths";
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

        optionsMode = lib.mkOption {
          type = lib.types.enum [
            "auto"
            "strict"
            "free"
          ];
          default = "strict";
          description = "Mode for handling options.nix files: 'auto' (nest options under module path), 'strict' (check options match module path), 'free' (no restrictions)";
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

        colmena = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "colmena integration";
            };
          };
          default = { };
          description = "Colmena configuration";
        };

        flake = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Extra flake outputs to merge with FHS outputs";
        };

        systemContext = lib.mkOption {
          description = "Context generator dependent on system";
          default = _: { };
          type = lib.mkOptionType {
            name = "systemContext";
            description = "function system -> attrs";
            check = lib.isFunction;
            merge =
              loc: defs: system:
              lib.foldl' (acc: def: lib.recursiveUpdate acc (def.value system)) { } defs;
          };
        };
      };
    };

  # ================================================================
  # Core Logic
  # ================================================================
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
      optionsMode ? "strict",
      colmena ? {
        enable = false;
      },
      layout ? defaultLayout,
      systemContext ? _: { },
      ...
    }:
    let
      partOf = builtins.mapAttrs (
        name: value: x:
        elem x (value.subdirs)
      ) layout;

      # roots = [Path]

      roots = forFilter (layout.roots.subdirs or [ ]) (
        d:
        let
          p = self.outPath + "/${flakeFhsLib.trimPath d}";
        in
        if pathExists p then p else null
      );

      # system related context
      mkSysContext =
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
          userCtx = systemContext system;
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
        dict supportedSystems (
          system:
          let
            sysContext = mkSysContext system;
          in
          outputBuilder sysContext
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

      # Shared modules for both NixOS configurations and Colmena
      sharedModules =
        moduleTree.unguardedConfigPaths
        ++ concatFor moduleTree.guardedChildrenNodes (it: [
          (mkOptionsModule optionsMode it)
          (mkDefaultModule optionsMode it)
        ]);

      # Nixpkgs version module
      nixpkgsVersionModule = {
        system.nixos.revision = nixpkgs.rev or nixpkgs.dirtyRev or null;
        system.nixos.versionSuffix =
          if nixpkgs ? lastModifiedDate && nixpkgs ? shortRev then
            ".${builtins.substring 0 8 nixpkgs.lastModifiedDate}.${nixpkgs.shortRev}"
          else
            "";
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

      # collectFromRoots :: [String] -> SystemContext -> [PackageNode]
      collectFromRoots =
        subdirsList: sysContext:
        builtins.concatMap (
          root:
          let
            validSubdirs = forFilter subdirsList (
              subdir:
              let
                p = root + "/${subdir}";
              in
              if pathExists p then p else null
            );
          in
          builtins.concatMap (
            pkgRoot:
            evalScopedTree sysContext sysContext.scope { } (mkScopedTreeNode {
              path = pkgRoot;
              breadcrumbs = [ ];
            })
          ) validSubdirs
        ) roots;
    in
    {
      # Generate all flake outputs

      # outputs:
      #  pkgs/        # subdirs marked by package.nix
      #  modules/     # unguarded & guarded by options.nix
      #  hosts/       # marked by configuration.nix
      #  shells/      # top-level files & subdirs marked by shell.nix
      #  apps/        # top-level files & subdirs marked by default.nix
      #  utils/       # more/ and other .nix files
      #  checks/      # top-level files & subdirs marked by default.nix
      #  templates/   # top-level subdirs marked by templates.nix

      packages = eachSystem (
        sysContext: listToAttrs (collectFromRoots layout.packages.subdirs sysContext)
      );

      apps = eachSystem (
        sysContext:
        let
          inherit (flakeFhsLib.more sysContext.pkgs) inferMainProgram;
          # 1. Collect all packages from 'apps' directories
          rawApps = collectFromRoots layout.apps.subdirs sysContext;
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

      devShells = eachSystem (
        sysContext:
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
                        value = import (it.path + "/${fname}") sysContext;
                      }
                    else
                      null
                  )
                else if isShellsSubDir && pathExists (it.path + "/default.nix") then
                  # Case 2: shells/<name>/default.nix -> devShells.<name>
                  [
                    {
                      name = concatStringsSep "/" (tail it.breadcrumbs');
                      value = import (it.path + "/default.nix") sysContext;
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
              value = mkOptionsModule optionsMode it;
            }
            {
              name = (concatStringsSep "." it.modPath) + ".config";
              value = mkDefaultModule optionsMode it;
            }
          ])
        )
        // {
          default = {
            imports = moduleTree.unguardedConfigPaths;
          };
        };

      nixosConfigurations = listToAttrs (
        map (
          host:
          let
            sysContext = mkSysContext host.info.system;
            modules = [ (host.path + "/configuration.nix") ] ++ sharedModules;
          in
          {
            name = host.name;
            value = lib.nixosSystem {
              inherit (sysContext)
                system
                lib
                ;
              specialArgs = sysContext.specialArgs // {
                hostname = host.name;
              };
              modules = modules ++ [
                { nixpkgs.pkgs = sysContext.pkgs; }
                nixpkgsVersionModule
              ];
            };
          }
        ) validHosts
      );

      checks = eachSystem (sysContext: listToAttrs (collectFromRoots layout.checks.subdirs sysContext));

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
            pkgs.treefmt.withConfig { settings = import treefmtNix; }
        else if pathExists treefmtToml then
          pkgs.treefmt.withConfig { configFile = treefmtToml; }
        else
          pkgs.treefmt
      );
    }
    // (
      if colmena.enable then
        {
          colmenaHive = inputs.colmena.lib.makeHive (
            {
              meta = {
                nixpkgs = (mkSysContext (head supportedSystems)).pkgs;
                nodeNixpkgs = listToAttrs (
                  map (host: {
                    name = host.name;
                    value = (mkSysContext host.info.system).pkgs;
                  }) validHosts
                );
                nodeSpecialArgs = listToAttrs (
                  map (
                    host:
                    let
                      sysContext = mkSysContext host.info.system;
                    in
                    {
                      name = host.name;
                      value = sysContext.specialArgs // {
                        hostname = host.name;
                      };
                    }
                  ) validHosts
                );
              };
            }
            // listToAttrs (
              map (host: {
                name = host.name;
                value = {
                  deployment.allowLocalDeployment = true;
                  imports = [ (host.path + "/configuration.nix") ] ++ sharedModules ++ [ nixpkgsVersionModule ];
                };
              }) validHosts
            )
          );
        }
      else
        { }
    );
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
        optionsMode = config.optionsMode;
        colmena = config.colmena;
        nixpkgsConfig = config.nixpkgs.config;
        layout = config.layout;
        systemContext = config.systemContext;
      };
    in
    lib.recursiveUpdate fhsFlake config.flake;
}
