# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    foldl'
    map
    listToAttrs
    attrNames
    length
    intersectAttrs
    ;
in
rec {

  # dict' : [k] -> (k -> k') -> (k -> v) -> Dict k' v
  dict' =
    ks: fk: fv:
    listToAttrs (
      map (k: {
        name = fk k;
        value = fv k;
      }) ks
    );

  # disjoint : Dict k v -> Dict k v -> Bool
  disjoint = a: b: length (attrNames (intersectAttrs a b)) == 0;

  # merge2 : Dict k v -> Dict k v -> Dict k v
  # disjoint union 2 dict
  merge2 =
    a: b:
    assert (disjoint a b);
    a // b;

  # merge : [Dict k v] -> Dict k v
  # disjoint union
  merge =
    ds:
    foldl' (
      a: b:
      assert (disjoint a b);
      a // b
    ) { } ds;

  # union : [Dict k v] -> Dict k v
  #  similar to fold in Haskell
  union = ds: foldl' (a: b: a // b) { } ds;

  # unionFor : [a] -> (a -> Dict k v) -> Dict k v
  #  similar to foldMap in Haskell
  unionFor = ks: f: foldl' (a: b: a // b) { } (map f ks);

  # unionForItems : Dict k v -> (k -> v -> Dict k' v') -> Dict k' v'
  unionForItems = d: f: foldl' (a: b: a // b) { } (map (k: f k d.${k}) (attrNames d));
}
