# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS module system logic and output generation
#
# ================================================================
# 设计文档: 模块系统 (基于 default.nix 的统一模型)
# ================================================================
#
# ## 1. 核心概念
#
# 模块系统只有一种入口：`default.nix`（目录模块）或独立的 `.nix` 文件（单文件模块）。
# 没有"模块类型"的区分，只有 **guarded 配置文件** 这一文件级属性。
#
# ### 1.1 目录模块 (Directory Module)
# - 标识符: 目录包含 `default.nix`
# - 入口: `default.nix`（可写 options + config）
# - enable 注入: **无条件注入** `<modPath>.enable`（若 default.nix 未手动定义）
#   - 这是 enable-chain 自洽的前提：链路上每个模块都保证有 enable
# - 嵌套: 支持嵌套，子模块的 enable-chain 包含所有祖先模块的 enable
#
# ### 1.2 单文件模块 (Single File Module)
# - 标识符: 独立的 `.nix` 文件（不位于任何含 `default.nix` 的目录中）
# - 无 enable 注入，无 enable-chain
#
# ### 1.3 guarded 配置文件 (Guarded Config File)
# - 标识符: 文件名匹配配置的 guarded 后缀（默认 `.cfg.nix`）
# - 位置约束: 必须位于某个目录模块的子树内
# - 行为: 内容被 `mkIf (all-ancestor-enables && self-enable)` 包裹
# - 自动 import: 所属目录模块会自动收集并 import 其范围内的所有 .cfg.nix
#
# ## 2. enable-chain 的精确定义
#
# 一个 `.cfg.nix` 的 mkIf 条件 = 链路上**所有祖先模块**（有 `default.nix` 的祖先目录）
# 的 enable AND **自身所属模块**的 enable 之 AND。
#
# 中间目录若无 `default.nix`（只是路径组织用），不参与 enable-chain，但仍贡献 modPath 段。
#
# 示例:
#   modules/
#   └── network/              # 有 default.nix → 模块，进 chain
#       ├── default.nix       # 注入 network.enable
#       ├── net.cfg.nix       # mkIf config.network.enable
#       └── services/         # 无 default.nix → 路径段，不进 chain
#           └── web/           # 有 default.nix → 模块，进 chain
#               ├── default.nix  # 注入 network.services.web.enable
#               └── web.cfg.nix  # mkIf (config.network.enable && config.network.services.web.enable)
#
# ## 3. 核心数据结构
#
# type ModuleInfo = {
#   modPath :: [String];           # 模块路径段（含中间目录段）
#   path :: Path;                  # 文件系统路径
#   kind :: "file" | "directory";  # 单文件 or 目录模块
#   cfgFiles :: [Path];            # 目录模块: 其直接范围内的 .cfg.nix 列表; 单文件: 空
#   ancestorModulePaths :: [[String]];  # 链路上所有祖先模块的 modPath（不含自身）
# }
#
# ## 4. 输出结构
#
# - nixosModules.<modPath> - 每个模块的独立输出
# - nixosModules.default - 引入所有模块的默认入口
#
lib:
let
  inherit (builtins)
    head
    elem
    concatLists
    concatStringsSep
    pathExists
    removeAttrs
    listToAttrs
    ;

  inherit (lib)
    lsFiles
    hasSuffix
    forFilter
    isEmptyFile
    underDir
    ;

  # ================================================================
  # 1. collectModules - 单路径递归扫描
  # ================================================================

  # 单文件模块的固定后缀（不可配置）
  moduleSuffix = ".nix";

  # scanDir :: Path -> [String] -> [[String]] -> String -> [ModuleInfo]
  #
  # 在单个目录层级识别模块并递归子目录。
  #   path:         当前扫描的目录路径
  #   breadcrumbs:  从根到当前目录的路径段（含当前段）
  #   ancestorMods: 链路上所有祖先模块的 modPath 列表（不含当前）
  #   guardedSuffix: guarded 配置文件的后缀（默认 ".cfg.nix"）
  scanDir =
    path: breadcrumbs: ancestorMods: guardedSuffix:
    let
      files = lsFiles path;
      hasDefault = elem "default.nix" files;

      # 目录模块: 有 default.nix
      dirModule =
        if hasDefault then
          let
            modPath = breadcrumbs;
            # 收集本模块直接范围内的 .cfg.nix（递归子目录，但跳过子模块子树）
            cfgFiles = collectCfgFiles path guardedSuffix;
          in
          [
            {
              inherit modPath path cfgFiles;
              kind = "directory";
              ancestorModulePaths = ancestorMods;
            }
          ]
        else
          [ ];

      # 单文件模块: 仅当当前目录无 default.nix 且不在任何目录模块子树内时
      # （ancestorMods 为空保证不在任何目录模块子树内）
      # 识别 .nix 文件（排除 default.nix 和 .cfg.nix）
      singleFiles =
        if !hasDefault && ancestorMods == [ ] then
          forFilter files (
            f:
            if hasSuffix moduleSuffix f
               && f != "default.nix"
               && !(hasSuffix guardedSuffix f) then
              let
                name = lib.removeSuffix moduleSuffix f;
              in
              {
                modPath = breadcrumbs ++ [ name ];
                path = path + "/${f}";
                cfgFiles = [ ];
                kind = "file";
                ancestorModulePaths = [ ];
              }
            else
              null
          )
        else
          [ ];

      # 递归子目录
      # 若当前目录是模块，则它加入下一层的 ancestorMods；否则沿用
      nextAncestors = if hasDefault then ancestorMods ++ [ breadcrumbs ] else ancestorMods;
      subResults = concatLists (
        map (
          d: scanDir (path + "/${d}") (breadcrumbs ++ [ d ]) nextAncestors guardedSuffix
        ) (lib.lsDirs path)
      );
    in
    dirModule ++ singleFiles ++ subResults;

  # collectCfgFiles :: Path -> String -> [Path]
  # 收集目录模块直接范围内的所有 .cfg.nix:
  #   - 当前目录的 .cfg.nix 文件
  #   - 递归子目录中的 .cfg.nix，但遇到含 default.nix 的子目录（子模块）就停止下钻
  # 这保证每个 .cfg.nix 只被其最近的所属模块收集一次
  collectCfgFiles =
    dir: guardedSuffix:
    let
      files = lsFiles dir;
      dirs = lib.lsDirs dir;
      currentCfg = forFilter files (
        f: if hasSuffix guardedSuffix f then dir + "/${f}" else null
      );
      subCfg = concatLists (
        forFilter dirs (
          d:
          let
            sub = dir + "/${d}";
            subHasDefault = pathExists (sub + "/default.nix");
          in
          if subHasDefault then null else collectCfgFiles sub guardedSuffix
        )
      );
    in
    currentCfg ++ subCfg;

  # collectModules :: Path -> String -> [ModuleInfo]
  # 过滤 modPath 为空的模块（根目录的 default.nix），因为它会生成无名的 nixosModule，语义不明
  collectModules =
    root: guardedSuffix:
    let
      all = scanDir root [ ] [ ] guardedSuffix;
    in
    lib.filter (m: m.modPath != [ ]) all;

  # ================================================================
  # 2. Module Wrapper
  # ================================================================

  # genericWrapModule ::
  #   { injectEnable :: Bool
  #   , enableCheckPath :: [[String]]?
  #   } -> ModuleInfo -> (Path | Module) -> Module
  #
  # 统一模块包装引擎:
  #   - enable 选项注入（injectEnable=true 且 options 中无同名 enable 时）
  #   - mkIf 包裹（enableCheckPath 非 null 时按 chain 计算条件）
  #   - 本地 imports 的递归包装
  genericWrapModule =
    {
      injectEnable,
      enableCheckPath ? null,
    }:
    moduleInfo: module:
    let
      modPath = moduleInfo.modPath;

      isPath = builtins.isPath module || builtins.isString module;
      file = if isPath then module else null;

      # 空文件视为空模块 `{}`，避免 Nix 对 0 字节文件报语法错
      # 否则正常 import（目录模块的 default.nix 也走这里，Nix 会自动找到目录下的 default.nix）
      raw =
        if isPath && isEmptyFile module then
          { }
        else if isPath then
          import module
        else
          module;

      transform =
        content:
        { config, lib, ... }:
        let
          opts = content.options or { };

          # 1. Enable 选项注入（仅在未手动定义时）
          enablePath = modPath ++ [ "enable" ];
          finalOpts =
            if injectEnable && !lib.hasAttrByPath enablePath opts then
              lib.recursiveUpdate opts (
                lib.setAttrByPath modPath {
                  enable = lib.mkEnableOption (concatStringsSep "." modPath);
                }
              )
            else
              opts;

          # 2. Config 合并（explicit `config = ...` + implicit 顶层属性）
          # removeAttrs 列表：NixOS 模块系统的保留字段，不应进入 config
          explicitConfig = content.config or { };
          implicitConfig = removeAttrs content [
            "imports"
            "options"
            "config"
            "_file"
            "key"
            "meta"
            "class"
            "disabledModules"
            "__functor"
            "__functionArgs"
          ];
          mergedConfig = lib.mkMerge [
            explicitConfig
            implicitConfig
          ];

          # 3. mkIf 条件（仅对 .cfg.nix 应用 enable-chain）
          # enableCheckPath 为 null 时表示 default.nix，config 总是生效
          mkIfCondition =
            if enableCheckPath != null then
              builtins.all (p: lib.attrByPath (p ++ [ "enable" ]) false config) enableCheckPath
            else
              true;

          # 4. 递归包装本地 imports（保持模块包装一致性）
          originalImports = content.imports or [ ];
          wrappedImports = map (
            i:
            let
              isPathOrString = builtins.isPath i || builtins.isString i;
              shouldWrap =
                if isPathOrString && file != null then
                  # 目录模块的 imports 基准是目录本身；文件模块的基准是所在目录
                  let
                    isModDir = builtins.pathExists (file + "/.");
                    currentDir = if isModDir then file else builtins.dirOf file;
                  in
                  underDir currentDir i
                else
                  false;
            in
            if shouldWrap then wrapPlainModule moduleInfo i else i
          ) originalImports;
        in
        {
          imports = wrappedImports;
          options = finalOpts;
          config = lib.mkIf mkIfCondition mergedConfig;
        };

      functor =
        if builtins.isFunction raw then
          {
            __functor = self: args: transform (raw args) args;
            __functionArgs = builtins.functionArgs raw;
          }
        else
          { __functor = self: args: transform raw args; };
    in
    if file != null then
      {
        _file = file;
        key = toString file + ":fhs-wrapped";
        imports = [ functor ];
      }
    else
      functor;

  # wrapPlainModule :: ModuleInfo -> (Path | Module) -> Module
  # 递归包装 imports 中的本地文件（不注入 enable，不包裹 mkIf）
  wrapPlainModule =
    moduleInfo: module:
    genericWrapModule {
      injectEnable = false;
    } moduleInfo module;

  # ================================================================
  # 3. Specialized Wrappers
  # ================================================================

  # wrapDirectoryModule :: ModuleInfo -> Module
  # 包装目录模块: default.nix（含 enable 注入）+ 所有 .cfg.nix（含 enable-chain）
  wrapDirectoryModule =
    moduleInfo:
    let
      # default.nix: 无条件注入 enable（保证 enable-chain 自洽）
      defaultWrapped = genericWrapModule {
        injectEnable = true;
      } moduleInfo (moduleInfo.path + "/default.nix");

      # enable-chain: 所有祖先模块 + 自身
      fullChain = moduleInfo.ancestorModulePaths ++ [ moduleInfo.modPath ];

      # 每个 .cfg.nix: 用完整 enable-chain 包裹
      cfgWrapped = map (
        cfgPath:
        genericWrapModule {
          injectEnable = false;
          enableCheckPath = fullChain;
        } moduleInfo cfgPath
      ) moduleInfo.cfgFiles;
    in
    {
      key = toString moduleInfo.path;
      imports = [ defaultWrapped ] ++ cfgWrapped;
    };

  # wrapSingleModule :: ModuleInfo -> Module
  # 包装单文件模块: 无 enable 注入，无 mkIf 包裹
  wrapSingleModule =
    moduleInfo:
    genericWrapModule {
      injectEnable = false;
    } moduleInfo moduleInfo.path;

  # wrapModule :: ModuleInfo -> Module
  wrapModule =
    moduleInfo:
    if moduleInfo.kind == "directory" then
      wrapDirectoryModule moduleInfo
    else
      wrapSingleModule moduleInfo;

  # ================================================================
  # 4. Strict Options Validation (post-evaluation)
  # ================================================================

  isOptionLeaf = val: builtins.isAttrs val && val._type or null == "option";

  collectOptionLeaves = options:
    let
      walk = prefix: opts:
        if !builtins.isAttrs opts then [ ]
        else
          concatLists (
            lib.mapAttrsToList (name: val:
              if prefix == [ ] && name == "_module" then [ ]
              else
                let loc = prefix ++ [ name ];
                in
                if isOptionLeaf val then
                  [ { inherit loc; inherit (val) declarations; } ]
                else if builtins.isAttrs val then
                  walk loc val
                else
                  [ ]
            ) opts
          );
    in
    walk [ ] options;

  fileToModPath =
    infos: file:
    let
      fileStr = toString file;
      sorted = builtins.sort (a: b:
        builtins.stringLength (toString a.path) > builtins.stringLength (toString b.path)
      ) infos;
      match = lib.findFirst (info:
        let infoStr = toString info.path;
        in lib.hasPrefix (infoStr + "/") fileStr
      ) null sorted;
    in
    if match == null then null else match.modPath;

  validateOptionNamespaces = infos: options:
    let
      leaves = collectOptionLeaves options;
      locStartsWith = prefix: loc:
        builtins.length prefix <= builtins.length loc
        && lib.take (builtins.length prefix) loc == prefix;
    in
    lib.filter (leaf:
      let
        expected = lib.filter (x: x != null) (
          map (fileToModPath infos) leaf.declarations
        );
      in
      expected != [ ]
      && !(lib.any (modPath: locStartsWith modPath leaf.loc) expected)
    ) (
      map (leaf: leaf // {
        expectedModPath =
          let
            exp = lib.filter (x: x != null) (
              map (fileToModPath infos) leaf.declarations
            );
          in
          if exp != [ ] then head exp else [ ];
      }) leaves
    );

  mkStrictValidationModule = infos:
    { options, lib, ... }:
    let
      violations = validateOptionNamespaces infos options;
      formatViolation = v:
        let
          locStr = concatStringsSep "." v.loc;
          expectedStr = concatStringsSep "." v.expectedModPath;
          fileStr = toString (head v.declarations);
        in
        "strictOptions: option ${locStr} declared in ${fileStr} is not namespaced under expected ${expectedStr}";
    in
    {
      options.assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        internal = true;
      };
      config.assertions = map (v: {
        assertion = false;
        message = formatViolation v;
      }) violations;
    };

  # ================================================================
  # 5. Output Generation
  # ================================================================

  mkModulesOutputSingle =
    modulesDir: guardedSuffix:
    let
      moduleInfos = collectModules modulesDir guardedSuffix;
      modules = map (info: {
        name = concatStringsSep "/" info.modPath;
        value = wrapModule info;
      }) moduleInfos;
      defaultModule = {
        key = toString modulesDir + ":default";
        imports = map (m: m.value) modules;
      };
    in
    {
      inherit modules moduleInfos;
      default = defaultModule;
    };

  mkModulesOutput =
    {
      moduleDirs,
      guardedSuffix,
      strictOptions ? false,
    }:
    let
      allOutputs = map (
        dir: mkModulesOutputSingle dir guardedSuffix
      ) moduleDirs;

      allModules = concatLists (map (o: o.modules) allOutputs);
      allModuleInfos = concatLists (map (o: o.moduleInfos) allOutputs);

      # 重复模块名检测：用 builtins.seq 绑定到 nixosModules 的求值路径上
      # （Nix 惰性求值要求检测逻辑在返回值中被显式引用才会触发）
      moduleNames = map (m: m.name) allModules;
      duplicates = builtins.filter (name: lib.count (n: n == name) moduleNames > 1) (lib.unique moduleNames);
      dupGuard =
        if lib.length duplicates > 0 then
          throw "Duplicate module names found: ${concatStringsSep ", " duplicates}"
        else
          { };

      defaultModule = {
        key = "default";
        imports = map (m: m.value) allModules
          ++ lib.optional strictOptions (mkStrictValidationModule allModuleInfos);
      };

      # 将 dupGuard 通过 builtins.seq 强制求值，再返回 nixosModules
      # 这样只要 nixosModules 被引用（哪怕只是 attrNames），dupGuard 就会触发
      nixosModulesValue =
        listToAttrs allModules
        // (
          if allModules == [ ] then
            { }
          else
            {
              default = defaultModule;
            }
        );
    in
    {
      nixosModules = builtins.seq dupGuard nixosModulesValue;
    };

in
{
  inherit
    collectModules
    genericWrapModule
    wrapPlainModule
    wrapDirectoryModule
    wrapSingleModule
    wrapModule
    collectOptionLeaves
    validateOptionNamespaces
    mkStrictValidationModule
    mkModulesOutputSingle
    mkModulesOutput
    ;
}
