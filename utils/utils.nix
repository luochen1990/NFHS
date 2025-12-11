# Chainable utils preparation system
# Adapted from ~/ws/nixos/tools/default.nix pattern

let
  inherit (import ./dict.nix) unionFor;
  inherit (import ./file.nix) findFiles hasPostfix;

  # Import modules with function handling
  importOrCall =
    path: args:
    let
      module = import path;
    in
    if builtins.isFunction module then module args else module;

in
{
  prepareUtils =
    utilsPath:
    let
      # Level 1: builtins-only modules
      base = unionFor (findFiles (hasPostfix "nix") utilsPath) (path: importOrCall path { });

      # Check if more directory exists
      morePath = utilsPath + "/more";
      hasMore = builtins.pathExists morePath;
    in
    base
    // {
      more =
        { lib }:
        let
          # Level 2: lib-dependent modules (flatten)
          level2 =
            if hasMore then
              unionFor (findFiles (hasPostfix "nix") morePath) (
                fname:
                let
                  result = importOrCall fname { inherit lib; };
                in
                if builtins.isAttrs result then
                  result
                else
                  {
                    "${builtins.replaceStrings [ ".nix" ] [ "" ] (builtins.baseNameOf fname)}" = result;
                  }
              )
            else
              { };

          moreMorePath = morePath + "/more";
        in
        base
        // level2
        // {
          more =
            { pkgs }:
            if builtins.pathExists moreMorePath then
              unionFor (findFiles (hasPostfix "nix") moreMorePath) (path: {
                "${builtins.replaceStrings [ ".nix" ] [ "" ] (builtins.baseNameOf path)}" = importOrCall path {
                  inherit lib pkgs;
                };
              })
            else
              { };
        };
    };
}
