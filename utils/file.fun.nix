# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    filter
    map
    readDir
    attrNames
    match
    concatMap
    elem
    length
    concatLists
    ;
in
rec {

  # isHidden : Path -> Bool
  isHidden = (path: match "\\..*" path != null);

  # isNotHidden : Path -> Bool
  isNotHidden = (path: match "\\..*" path == null);

  # hasPostfix : String -> Path -> Bool
  hasPostfix =
    postfix:
    let
      pat = ".*\\." + builtins.replaceStrings [ "." ] [ "\\." ] postfix;
    in
    path: match pat (toString path) != null;

  # underDir : Path -> Path -> Bool
  # judge whether the path is under the directory
  underDir =
    directoryPath: path: match ("^" + toString directoryPath + "/.*") (toString path) != null;

  # list all sub directories including hidden ones
  # lsDirsAll : Path -> [DirName]
  lsDirsAll = (
    path:
    let
      d = readDir path;
    in
    filter (k: d.${k} == "directory") (attrNames d)
  );

  # lsDirs : Path -> [DirName]
  lsDirs = (
    path:
    let
      d = readDir path;
    in
    filter (k: d.${k} == "directory" && (isNotHidden k)) (attrNames d)
  );

  # subDirsAll : Path -> [Path]
  # subDirs : Path -> [Path]

  # lsFilesAll : Path -> [FileName]
  lsFilesAll =
    path:
    let
      d = readDir path;
    in
    filter (k: d.${k} == "regular") (attrNames d);

  # lsFiles : Path -> [FileName]
  lsFiles =
    path:
    let
      d = readDir path;
    in
    filter (k: d.${k} == "regular" && (isNotHidden k)) (attrNames d);

  # elemAt : Int -> [a] -> a
  elemAt =
    index:
    if index < 0 then
      list: builtins.elemAt list (length list + index)
    else
      list: builtins.elemAt list index;

  # subDirsRec : Path -> ({depth: Int, path: Path, name: String, breadcrumbs: List String} -> {pick: Bool, into: Bool, out: a}) -> [a]
  subDirsRec =
    root: test:
    let
      recur =
        root: test: depth: breadcrumbs:
        concatMap (
          name:
          #NOTE: assert (builtins.concatStringsSep "/" (breadcrumbs ++ [name]) == path)
          let
            path = root + ("/" + name);
            t = test {
              inherit
                depth
                path
                name
                breadcrumbs
                ;
            };
          in
          (if t.pick then [ t.out ] else [ ])
          ++ (if t.into then (recur path test (depth + 1) (breadcrumbs ++ [ name ])) else [ ])
        ) (lsDirsAll root);
    in
    recur root test 0 [ ];

  # findFiles : (Path -> Bool) -> Path -> [Path]
  findFiles =
    let
      forFilter = xs: f: filter (x: x != null) (map f xs);
    in
    test: path:
    let
      d = readDir path;
    in
    forFilter (attrNames d) (
      k:
      if d.${k} == "regular" then
        (
          let
            p = (path + "/${k}");
            t = test p;
          in
          if t then p else null
        )
      else
        null
    );

  # findFilesRec : (Path -> Bool) -> Path -> [FilePath]
  findFilesRec =
    test: root:
    findFiles test root
    ++ concatLists (
      subDirsRec root (
        { path, ... }:
        {
          pick = true;
          into = true;
          out = findFiles test path;
        }
      )
    );

  # findSubDirsContains : Path -> String -> [Path]
  findSubDirsContains =
    root: filename:
    let
      # dirContainsFile : Path -> String -> Bool
      dirContainsFile = dir: filename: elem filename (attrNames (readDir dir));
    in
    concatMap (
      dir:
      let
        p = root + "/${dir}";
      in
      (if dirContainsFile p filename then [ dir ] else [ ])
      ++ map (s: "${dir}/${s}") (findSubDirsContains p filename)
    ) (lsDirsAll root);

}