# NFHS core implementation
# mkFlake function that auto-generates flake outputs from directory structure
lib:
let
  inherit (builtins)
    pathExists
    listToAttrs
    concatStringsSep
    tail
    concatLists
    elem
    filter
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
    subDirsRec
    exploreDir
    hasPostfix
    ;

  mkOptionsModule =
    {
      paths,
      modPath,
    }:
    moduleArgs:
    let
      rawOptions = unionFor paths (path: import (path + "/options.nix") moduleArgs);
      virtualEnableOption = lib.mkEnableOption (concatStringsSep "." modPath);
      filledOptions = {
        enable = virtualEnableOption;
      }
      // rawOptions;
    in
    {
      options = lib.attrsets.setAttrByPath modPath filledOptions;
    };

  mkGuardedTreeNode =
    {
      modPath,
      paths,
      optionsModule,
    }:
    let
      unguardedConfigPaths = concatLists (
        exploreDir paths (it: rec {
          options-dot-nix = it.path + "/options.nix";
          guarded = pathExists options-dot-nix;
          into = !guarded;
          pick = !guarded;
          out = forFilter (lsFiles it.path) (
            fname: if hasPostfix "nix" fname then (it.path + "/${fname}") else null
          );
        })
      );

      guardedSubdirs = exploreDir paths (it: rec {
        options-dot-nix = it.path + "/options.nix";
        guarded = pathExists options-dot-nix;
        into = !guarded;
        pick = guarded;
        out = {
          modPath = it.breadcrumbs';
          paths = [ it.path ];
          optionsModule = mkOptionsModule {
            modPath = it.breadcrumbs';
            paths = [ it.path ];
          };
        };
      });

      # TODO: 这里需要对 modPath 进行去重，暂时先假设没有重复的情况
      children = for guardedSubdirs (subdir: mkGuardedTreeNode subdir);
    in
    {
      inherit
        modPath
        paths
        optionsModule
        unguardedConfigPaths
        children
        ;
    };
in
{
  # Main mkFlake function
  mkFlake =
    {
      self,
      nixpkgs,
      inputs ? self.inputs,
      roots ? [
        self.outPath
      ]
      ++ filter pathExists [
        (self.outPath + "/nix")
      ],
      lib ? nixpkgs.lib, # 这里用户提供的 lib 是不附带自定义工具函数的标准库lib
      supportedSystems ? lib.systems.flakeExposed,
      nixpkgsConfig ? {
        allowUnfree = true;
      },
      ...
    }:
    let
      outline.packages = rec {
        subdirs = [
          "pkgs"
          "packages"
        ];
        judge = x: elem x subdirs;
      };

      outline.nixosModules = rec {
        subdirs = [
          "modules"
          "nixosModules"
        ];
        judge = x: elem x subdirs;
      };

      outline.nixosConfigurations = rec {
        subdirs = [
          "profiles"
          "hosts"
          "nixosConfigurations"
        ];
        judge = x: elem x subdirs;
      };

      outline.devShells = rec {
        subdirs = [
          "shells"
          "devShells"
        ];
        judge = x: elem x subdirs;
      };

      outline.apps = rec {
        subdirs = [ "apps" ];
        judge = x: elem x subdirs;
      };

      outline.lib = rec {
        subdirs = [
          "lib"
          "tools"
          "utils"
        ];
        judge = x: elem x subdirs;
      };

      outline.checks = rec {
        subdirs = [ "checks" ];
        judge = x: elem x subdirs;
      };

      outline.templates = rec {
        subdirs = [ "templates" ];
        judge = x: elem x subdirs;
      };

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
          lib' = prepareLib {
            inherit roots pkgs;
            libSubdirs = outline.lib.subdirs;
            lib = lib;
          };
          specialArgs = {
            inherit
              self
              system
              #pkgs
              #lib
              inputs
              ;
            lib = lib' // lib;
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

      moduleSets =
        let
          moduleTree = mkGuardedTreeNode {
            modPath = [ ];
            paths = filter pathExists (map (root: root + "/modules") roots);
            optionsModule = { };
          };
        in
        {
          guardedToplevelModules = moduleTree.children;
          unguardedConfigPaths = moduleTree.unguardedConfigPaths;
        };
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
            into = it.depth == 0 && outline.packages.judge it.name || it.depth >= 1;
            pick = it.depth >= 1 && pathExists package-dot-nix;
            out = {
              name = concatStringsSep "/" (tail it.breadcrumbs');
              value = context.pkgs.callPackage package-dot-nix { };
            };
          })
        )
      );

      devShells = eachSystem (
        context:
        listToAttrs (
          exploreDir roots (it: rec {
            default-dot-nix = it.path + "/default.nix";
            into = it.depth == 0 && outline.devShells.judge it.name || it.depth >= 1;
            pick = it.depth == 1 && pathExists default-dot-nix;
            out = {
              name = concatStringsSep "/" (tail it.breadcrumbs');
              #value = context.pkgs.callPackage default-dot-nix { };
              value = import default-dot-nix context;
            };
          })
        )
      );

      nixosModules =
        listToAttrs (
          concatFor moduleSets.guardedToplevelModules (it: [
            {
              name = (concatStringsSep "." it.modPath) + ".options";
              value = it.optionsModule;
            }
            {
              name = (concatStringsSep "." it.modPath) + ".config";
              value = (
                args@{
                  lib,
                  config,
                  ...
                }:
                let
                  loadModule =
                    path:
                    let
                      m = import path;
                    in
                    if builtins.isFunction m then m args else m;
                in
                {
                  config = lib.mkIf (lib.attrsets.getAttrFromPath it.modPath config).enable (
                    lib.mkMerge (map loadModule it.unguardedConfigPaths)
                  );
                }
              );
            }
          ])
        )
        // {
          default = {
            imports = moduleSets.unguardedConfigPaths;
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
              ++ moduleSets.unguardedConfigPaths
              ++ concatFor moduleSets.guardedToplevelModules (it: [
                # Options module (always imported)
                it.optionsModule
                # Config module (guarded by enable option)
                (
                  args@{
                    lib,
                    config,
                    ...
                  }:
                  let
                    loadModule =
                      path:
                      let
                        m = import path;
                      in
                      if builtins.isFunction m then m args else m;
                  in
                  {
                    config = lib.mkIf (lib.attrsets.getAttrFromPath it.modPath config).enable (
                      lib.mkMerge (map loadModule it.unguardedConfigPaths)
                    );
                  }
                )
              ]);
              # TODO: partial load
              # config = lib.evalModules {
              #   modules = [ ];
              #   specialArgs = { };
              #   args = { };
              #   check = true;
              # };
            in
            lib.nixosSystem {
              #lib.nixosSystem {
              inherit (context)
                #self
                system
                pkgs
                lib
                specialArgs
                ;
              inherit modules;
            };
        in
        listToAttrs (
          exploreDir roots (it: rec {
            configuration-dot-nix = it.path + "/configuration.nix";
            marked = pathExists configuration-dot-nix;
            into = it.depth == 0 && outline.nixosConfigurations.judge it.name;
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
        libSubdirs = outline.lib.subdirs;
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
      formatter = eachSystem ({ pkgs, ... }: pkgs.nixfmt-tree);
    };
}
