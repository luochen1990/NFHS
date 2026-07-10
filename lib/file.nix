# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# the tool functions which is frequently used but not contained in nixpkgs.lib
let
  inherit (builtins)
    filter
    map
    readFile
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

  # isEmptyFile : Path -> Bool
  isEmptyFile = path: match "[[:space:]]*" (readFile path) != null;

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

  # hasSuffix : String -> Path -> Bool
  hasSuffix =
    suffix: path:
    assert builtins.substring 0 1 suffix == ".";
    let
      str = toString path;
      strLen = builtins.stringLength str;
      sufLen = builtins.stringLength suffix;
    in
    strLen >= sufLen && builtins.substring (strLen - sufLen) sufLen str == suffix;

  # underDir : Path -> Path -> Bool
  # judge whether the path is under the directory
  underDir =
    directoryPath: path:
    match ("^" + builtins.unsafeDiscardStringContext (toString directoryPath) + "/.*") (toString path)
    != null;

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
    test: path:
    let
      d = readDir path;
    in
    filter (x: x != null) (map (
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
    ) (attrNames d));

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

  # scanFilesBySuffix : String -> Path -> [Path]
  # 扫描目录中具有指定后缀的文件，返回文件路径列表
  scanFilesBySuffix =
    suffix: dir: if builtins.pathExists dir then (findFilesRec (hasSuffix suffix) dir) else [ ];

  # importUnguardedFiles : String -> Path -> [Path]
  #
  # 收集目录下的文件，尊重模块边界
  #
  # 行为:
  # - 收集当前目录下匹配后缀的文件
  # - 对于子目录:
  #   - 如果有 options.nix (guarded module)，跳过（由 flake-fhs 处理）
  #   - 如果有 default.nix，跳过（它有自己的导入逻辑）
  #   - 否则，递归处理
  #
  # 职责边界:
  # - 这个函数只负责收集 unguarded 的配置文件
  # - 有 default.nix 的目录由其他机制处理（如 flake-fhs 或手动导入）
  # - guarded module 由 flake-fhs 自动生成虚拟 default.nix
  #
  # 示例:
  #   # bedrock/default.nix
  #   { tools, ... }: {
  #     imports = tools.importUnguardedFiles ".mod.nix" ./.;
  #   }
  #
  importUnguardedFiles =
    suffix: root:
    let
      d = readDir root;
      names = attrNames d;

      # 收集当前目录下的文件
      currentFiles = filter (x: x != null) (map (
        name: if d.${name} == "regular" && hasSuffix suffix name then root + "/${name}" else null
      ) names);

      # 处理子目录
      subDirImports = filter (x: x != null) (map (
        name:
        if d.${name} == "directory" && !isHidden name then
          let
            subPath = root + "/${name}";
            optionsExists = builtins.pathExists (subPath + "/options.nix");
            defaultExists = builtins.pathExists (subPath + "/default.nix");
          in
          if optionsExists || defaultExists then
            # 有 options.nix 或 default.nix，跳过（由其他机制处理）
            null
          else
            # 普通 unguarded 目录，递归
            importUnguardedFiles suffix subPath
        else
          null
      ) names);
    in
    currentFiles ++ concatLists subDirImports;

  # trimPath : Path -> String
  trimPath =
    path:
    let
      s = toString path;
      len = builtins.stringLength s;
      start = if len > 0 && builtins.substring 0 1 s == "/" then 1 else 0;
      end = if len > start && builtins.substring (len - 1) 1 s == "/" then len - 1 else len;
    in
    builtins.substring start (end - start) s;
}
