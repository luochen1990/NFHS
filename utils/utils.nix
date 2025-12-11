# Chainable utils preparation system
# Directly adapted from ~/ws/nixos/tools/default.nix pattern
# With flattening for Level 2 modules

let
  inherit (import ./list.nix) concatMap for;
  inherit (import ./dict.nix) unionFor;

  # Find files with specific postfix
  hasPostfix = postfix: path:
    builtins.match ".*\\.${postfix}$" (builtins.baseNameOf path) != null;

  # Find files in directory, excluding subdirectories and utils.nix
  findFiles = pred: dir:
    let
      dirContent = builtins.readDir dir;
      regularFiles = builtins.filter (name:
        dirContent.${name} == "regular" && name != "utils.nix"
      ) (builtins.attrNames dirContent);
    in
    builtins.filter (path: pred path) (map (name: dir + "/${name}") regularFiles);

in
{
  # Main prepareUtils function
  prepareUtils = utilsPath:
    let
      # Level 1: builtins-only modules (current directory)
      # Handle both direct exports and functions
      level1 =
        let
          modules = findFiles (hasPostfix "nix") utilsPath;
          # For each module, import it. If it's a function, call it with {}
          processModule = path:
            let module = import path;
            in if builtins.isFunction module then module {} else module;
          # Merge all module exports
          mergeModules = modules:
            builtins.foldl' (acc: module: acc // (processModule module)) {} modules;
        in
        mergeModules modules;

      # Check if more directory exists
      morePath = utilsPath + "/more";
      hasMore = builtins.pathExists morePath;
    in
    level1 // {
      # more() method to access Level 2 and Level 3 (renamed from useLib)
      more = libArgs:
        let
          # Level 2: lib-dependent modules (flatten them like useLib in original)
          level2 = if hasMore then
            unionFor (findFiles (hasPostfix "nix") morePath) (fname:
              let result = import fname libArgs;
              in if builtins.isAttrs result then result else { "${builtins.replaceStrings [".nix"] [""] (builtins.baseNameOf fname)}" = result; }
            )
          else {};

          # Check if more/more directory exists
          moreMorePath = morePath + "/more";
          hasMoreMore = builtins.pathExists moreMorePath;
        in
        level2 // {
          # more() method to access Level 3 (renamed from usePkgs)
          more = pkgsArgs:
            if hasMoreMore then
              let
                allArgs = libArgs // pkgsArgs;
                # Import Level 3 modules without flattening - keep filename as key
                importLevel3 = path:
                  let
                    basename = builtins.replaceStrings [".nix"] [""] (builtins.baseNameOf path);
                  in
                  { "${basename}" = import path allArgs; };
              in
              unionFor (findFiles (hasPostfix "nix") moreMorePath) importLevel3
            else {};
        };
    };
}