# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    map
    filter
    tail
    head
    concatLists
    ;
in
rec {

  # for : [a] -> (a -> b) -> [b]
  for = xs: f: map f xs;

  # forFilter : [a] -> (a -> Maybe b) -> [b]
  forFilter = xs: f: filter (x: x != null) (map f xs);

  # concatFor : [a] -> (a -> [b]) -> [b]
  concatFor = xs: f: concatLists (map f xs);

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

}
