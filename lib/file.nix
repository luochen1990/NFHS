# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
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
  isHidden = path: match "\\..*" path != null;

  # isNotHidden : Path -> Bool
  isNotHidden = path: match "\\..*" path == null;

  # isNonEmptyDir : Path -> Bool
  isNonEmptyDir =
    path:
    if builtins.pathExists path && builtins.typeOf path == "path" then
      let
        content = builtins.readDir path;
      in
      # 如果 readDir 返回的属性集不等于空集 {}，则说明目录非空
      content != { }
    else
      false;

  # hasPostfix : String -> Path -> Bool
  hasPostfix = postfix: hasSuffix ("." + postfix);

  # hasSuffix : String -> Path -> Bool
  hasSuffix =
    suffix: path:
    let
      str = toString path;
      strLen = builtins.stringLength str;
      sufLen = builtins.stringLength suffix;
    in
    assert builtins.substring 0 1 suffix == ".";
    strLen >= sufLen && builtins.substring (strLen - sufLen) sufLen str == suffix;

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

  # lsDirPaths : Path -> [Path]
  lsDirPaths = path: map (subdir: path + "/${subdir}") (lsDirs path);

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

  # subDirsRec : Path -> Picker a -> [a]
  subDirsRec = root: exploreDir [ root ];

  # type Picker a = { path: Path, name: Text, breadcrumbs: List Text, depth: Int, root: Path } -> { pick: Bool, out: a, into: Bool }
  # exploreDir : [Path] -> Picker a -> [a]
  exploreDir =
    roots: picker:
    let
      recur =
        root: current: picker: depth: breadcrumbs:
        concatMap (
          name:
          let
            path = current + ("/" + name);
            t = picker {
              inherit
                root
                depth # assert (if current == root then depth == 0)
                breadcrumbs # assert (length breadcrumbs == depth)
                name
                path # assert (path == root + concatMap (x: "/${x}") breadcrumbs')
                ;
              breadcrumbs' = breadcrumbs ++ [ name ];
            };
          in
          (if t.pick then [ t.out ] else [ ])
          ++ (if t.into then (recur root path picker (depth + 1) (breadcrumbs ++ [ name ])) else [ ])
        ) (lsDirsAll current);
    in
    concatMap (root: recur root root picker 0 [ ]) roots;

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
            p = path + "/${k}";
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

  # scanFilesByPostfix : String -> Path -> [Path]
  # 扫描目录中具有指定后缀的文件，返回文件路径列表
  scanFilesByPostfix =
    postfix: dir: if builtins.pathExists dir then (findFilesRec (hasPostfix postfix) dir) else [ ];
}
