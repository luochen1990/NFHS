# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    map
    filter
    tail
    head
    concatLists
    length
    ;
in
rec {

  # for : [a] -> (a -> b) -> [b]
  for = xs: f: map f xs;

  # forFilter : [a] -> (a -> Maybe b) -> [b]
  forFilter = xs: f: filter (x: x != null) (map f xs);

  # mapFilter : (a -> Maybe b) -> [a] -> [b]
  mapFilter = f: xs: filter (x: x != null) (map f xs);

  # forWithIndex : [a] -> (Int -> a -> b) -> [b]
  forWithIndex =
    l: f:
    (builtins.foldl'
      (
        { i, l' }:
        x: {
          i = i + 1;
          l' = l' ++ [ (f i x) ];
        }
      )
      {
        i = 0;
        l' = [ ];
      }
      l
    ).l';

  # forItems : Dict k v -> (k -> v -> a) -> [a]
  forItems = d: f: map (k: f k d.${k}) (builtins.attrNames d);

  # concatFor : [a] -> (a -> [b]) -> [b]
  concatFor = xs: f: concatLists (map f xs);

  # concatMap : (a -> [b]) -> [a] -> [b]
  concatMap = f: xs: concatLists (map f xs);

  # powerset : [a] -> [[a]]
  powerset =
    xs:
    if xs == [ ] then
      [ [ ] ]
    else
      let
        ps = powerset (tail xs);
      in
      ps ++ (map (ys: [ (head xs) ] ++ ys) ps);

  # cartesianProduct : [[a]] -> [[a]]
  cartesianProduct =
    lists:
    let
      tailProduct = cartesianProduct (builtins.tail lists);
    in
    if builtins.length lists == 0 then
      [ [ ] ]
    else
      builtins.concatMap (item: builtins.map (sublist: [ item ] ++ sublist) tailProduct) (
        builtins.head lists
      );

  # not-empty : [a] -> Bool
  not-empty = xs: length xs > 0;

  # is-empty : [a] -> Bool
  is-empty = xs: length xs == 0;

}
