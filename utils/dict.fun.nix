# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    foldl'
    map
    listToAttrs
    attrNames
    ;
in
{

  # dict : [k] -> (k -> v) -> Dict k v
  #  or lib.genAttrs
  dict =
    ks: f:
    listToAttrs (
      map (k: {
        name = k;
        value = f k;
      }) ks
    );

  # dict' : [k] -> (k -> k') -> (k -> v) -> Dict k' v
  dict' =
    ks: fk: fv:
    listToAttrs (
      map (k: {
        name = fk k;
        value = fv k;
      }) ks
    );

  # unionFor : [a] -> (a -> Dict k v) -> Dict k v
  #  similar to foldMap in Haskell
  unionFor = ks: f: foldl' (a: b: a // b) { } (map f ks);

  # unionForItems : Dict k v -> (k -> v -> Dict k' v') -> Dict k' v'
  unionForItems = d: f: foldl' (a: b: a // b) { } (map (k: f k d.${k}) (attrNames d));

  # attrItems : Dict k v -> [(k, v)]
  # similar to toList in Haskell, and lib.attrsToList in nix
  attrItems =
    attrs:
    map (k: {
      k = k;
      v = attrs.${k};
    }) (builtins.attrNames attrs);
}