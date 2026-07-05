# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# Flake FHS module system logic and output generation
#
# ================================================================
# 设计文档: 模块系统 (重构版)
# ================================================================
#
# ## 1. 模块类型 (三种互斥类型)
#
# ### 1.1 Guarded Directory Module (受保护目录模块)
# - 标识符: 目录包含 options.nix
# - 特性:
#   - 自动生成 enable 选项
#   - 配置文件用 mkIf enable 包裹
#   - 嵌套模块检查所有父级的 enable
# - 约束: 不能有 default.nix (冲突错误)
# - 用例: 可选功能模块
#
# ### 1.2 Traditional Directory Module (传统目录模块)
# - 标识符: 目录包含 default.nix (无 options.nix)
# - 特性: 直接导出，无 enable 机制
# - 约束: 不支持嵌套 (有 default.nix 的子目录不被识别)
# - 用例: 配置集合，复杂模块
#
# ### 1.3 Single File Module (单文件模块)
# - 标识符: 独立的 .nix 文件
# - 特性: 直接导出，无 enable 机制
# - 用例: 简单模块
#
# ## 2. 核心数据结构
#
# ### 2.1 GuardedTree
# GuardedTree 是 guarded 模块的单一数据源 (SSOT)
#
# type GuardedTree = {
#   modPath :: [String];           # 模块路径段
#   path :: Path;                  # 文件系统路径
#   parentGuardedPaths :: [[String]];  # 父级 guarded 路径 (用于嵌套 mkIf)
#   fullGuardedPath :: [String];   # 完整路径 (包括自身)
#   files :: [String];             # 目录中的文件
#   unguardedFiles :: [Path];      # unguarded 配置文件路径
#   guardedChildren :: [GuardedTree];  # 子级 guarded 模块
# }
#
# ### 2.2 ModuleInfo
# ModuleInfo 描述所有三种模块类型
#
# type ModuleInfo = {
#   modPath :: [String];           # 模块路径段
#   path :: Path;                  # 文件系统路径
#   moduleType :: "guarded" | "traditional" | "single";
#   kind :: "file" | "directory";
#   hasOptions :: Bool;
#   hasDefault :: Bool;
#   unguardedFiles :: [Path];      # 仅 guarded 模块使用
#   parentGuardedPaths :: [[String]];  # 用于嵌套 mkIf
# }
#
# ## 3. 输出结构
#
# - nixosModules.<modPath> - 每个模块的独立输出
# - nixosModules.default - 引入所有模块的默认入口
#
lib:
let
  inherit (builtins)
    head
    tail
    elem
    hasAttr
    concatLists
    concatStringsSep
    pathExists
    removeAttrs
    listToAttrs
    foldl'
    ;

  inherit (lib)
    lsFiles
    exploreDir
    hasSuffix
    forFilter
    concatFor
    isEmptyFile
    underDir
    ;

  # ================================================================
  # 1. mkGuardedTree - Guarded 模块的 SSOT
  # ================================================================

  # mkGuardedTreeNode :: { modPath, path, parentGuardedPaths, suffix } -> GuardedTree
  #
  # 递归构建 guarded 模块树
  # - 检测 options.nix + default.nix 冲突
  # - 收集 unguarded 配置文件
  # - 跟踪父级 guarded 路径用于嵌套 mkIf
  #
  mkGuardedTreeNode =
    {
      modPath,
      path,
      parentGuardedPaths,
      suffix,
    }:
    let
      files = lsFiles path;
      hasOptions = elem "options.nix" files;
      hasDefault = elem "default.nix" files;

      # 根目录不允许有 options.nix (根节点是虚拟容器，不对应任何 guarded module)
      rootOptionsCheck = lib.assertMsg (modPath != [ ] || !hasOptions) (
        "Error at ${toString path}: Root module directory cannot have options.nix. "
        + "Guarded modules must be in subdirectories with meaningful paths."
      );

      # 冲突检测: options.nix 和 default.nix 不能共存
      # 使用 lib.assertMsg 提供精准的报错信息
      conflictCheck = lib.assertMsg (!(hasOptions && hasDefault)) (
        "Module conflict at ${toString path}: Cannot have both options.nix and default.nix. "
        + "Choose one module type: guarded (options.nix only) or traditional (default.nix only)."
      );

      # 收集 unguarded 配置文件 (仅对没有 default.nix 的 guarded 模块)
      # 使用配置的 suffix 来过滤文件
      # 递归收集当前目录和所有非-guarded 子目录中的配置文件 (无论是否有 default.nix)
      unguardedFiles =
        if hasOptions && !hasDefault then
          let
            # 当前目录的配置文件
            currentFiles = forFilter files (
              f: if hasSuffix suffix f && f != "options.nix" && f != "scope.nix" then path + "/${f}" else null
            );

            # 递归收集非-guarded 子目录中的配置文件
            # 注意：只跳过 guarded 目录，不跳过有 default.nix 的目录
            subFiles = exploreDir [ path ] (it: rec {
              options-dot-nix = it.path + "/options.nix";
              guarded = pathExists options-dot-nix;

              # 只进入非-guarded 的目录
              into = !guarded;
              # 收集所有非-guarded 目录中的配置文件
              pick = !guarded;

              currentFiles = lsFiles it.path;
              configFiles = forFilter currentFiles (
                f: if hasSuffix suffix f && f != "options.nix" && f != "scope.nix" then it.path + "/${f}" else null
              );

              out = configFiles;
            });
          in
          currentFiles ++ concatLists subFiles
        else
          [ ];

      # 完整 guarded 路径 (包括自身)
      fullGuardedPath = parentGuardedPaths ++ [ modPath ];

      # 递归处理子目录
      # 使用 exploreDir 提供的 breadcrumbs' 来正确累积 modPath
      guardedChildren = exploreDir [ path ] (it: rec {
        options-dot-nix = it.path + "/options.nix";
        default-dot-nix = it.path + "/default.nix";
        guarded = pathExists options-dot-nix;
        defaulted = pathExists default-dot-nix;

        # 进入非-defaulted 且非-guarded 的目录
        # guarded 目录会由 mkGuardedTreeNode 递归处理，所以不要在这里进入
        # 这样可以避免 guarded 目录被重复收集到父级和自己的 children 中
        into = !(defaulted || guarded);
        # 收集 guarded 目录
        pick = guarded;

        # 计算当前节点的 modPath (父级 modPath + 当前 breadcrumbs')
        currentModPath = modPath ++ it.breadcrumbs';

        # 计算父级 guarded 路径
        # 需要找到从根到当前的所有 guarded 祖先
        currentParentGuardedPaths = if hasOptions then fullGuardedPath else parentGuardedPaths;

        out = mkGuardedTreeNode {
          modPath = currentModPath;
          path = it.path;
          # 传递更新后的父级 guarded 路径给子级
          parentGuardedPaths = currentParentGuardedPaths;
          inherit suffix;
        };
      });
    in
    # 强制检测求值 (Nix 惰性求值需要显式使用)
    builtins.seq rootOptionsCheck (
      builtins.seq conflictCheck {
        inherit
          modPath
          path
          files
          unguardedFiles
          guardedChildren
          ;
        inherit parentGuardedPaths fullGuardedPath;
      }
    );

  # mkGuardedTree :: Path -> String -> GuardedTree
  mkGuardedTree =
    root: suffix:
    mkGuardedTreeNode {
      modPath = [ ];
      path = root;
      parentGuardedPaths = [ ];
      inherit suffix;
    };

  # ================================================================
  # 2. Generic Module Wrapper
  # ================================================================

  # genericWrapModule :: {
  #   injectEnable :: Bool,
  #   checkStrictOptions :: Bool,
  #   enableCheckPath :: [[String]]?
  # } -> ModuleInfo -> (Path | Module) -> Module
  #
  # 统一的模块包装引擎
  # - injectEnable: 是否注入 enable 选项
  # - checkStrictOptions: 是否检查选项严格匹配路径
  # - enableCheckPath: 用于嵌套 guarded 模块的 enable 检查路径
  #
  genericWrapModule =
    {
      injectEnable,
      checkStrictOptions,
      enableCheckPath ? null,
    }:
    moduleInfo: module:
    let
      modPath = moduleInfo.modPath;

      isPath = builtins.isPath module || builtins.isString module;
      file = if isPath then module else null;
      isDir = if isPath then builtins.pathExists (module + "/.") else false;

      raw =
        if isPath then
          if isDir then
            import module
          else if isEmptyFile module then
            { }
          else
            import module
        else
          module;

      # 严格模式验证
      checkStrict =
        opts: path:
        if opts == { } || path == [ ] then
          true
        else
          let
            h = head path;
          in
          if hasAttr h opts && removeAttrs opts [ h ] == { } then
            checkStrict opts.${h} (tail path)
          else
            false;

      # 转换模块内容
      transform =
        content:
        { config, lib, ... }:
        let
          opts = content.options or { };

          # 1. 严格验证
          _ =
            if checkStrictOptions && !checkStrict opts modPath then
              throw "Strict mode violation: options in ${toString file} must follow ${concatStringsSep "." modPath}"
            else
              null;

          # 2. Enable 选项注入
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

          # 3. Config 合并
          explicitConfig = content.config or { };
          implicitConfig = removeAttrs content [
            "imports"
            "options"
            "config"
            "_file"
            "meta"
            "disabledModules"
            "__functor"
            "__functionArgs"
          ];
          mergedConfig = lib.mkMerge [
            explicitConfig
            implicitConfig
          ];

          # 4. mkIf 条件 (用于嵌套 guarded 模块)
          # 使用 lib.attrByPath 安全访问属性，在属性不存在时返回 false
          # 这样可以避免在模块尚未完全加载时抛出错误
          mkIfCondition =
            if enableCheckPath != null then
              # 嵌套: 检查所有父级 enable 和自身
              # enableCheckPath 已经由 wrapGuardedConfig 计算好，包含了所有需要检查的路径
              let
                conditions = map (path: lib.attrByPath path false config) enableCheckPath;
              in
              foldl' (acc: cond: acc && cond) true conditions
            else if injectEnable then
              # 顶层: 只检查自身
              lib.attrByPath enablePath false config
            else
              true; # 无 enable 检查

          # 5. 递归包装本地 imports
          originalImports = content.imports or [ ];
          wrappedImports = map (
            i:
            let
              isPathOrString = builtins.isPath i || builtins.isString i;
              shouldWrap =
                if isPathOrString && file != null then
                  let
                    currentDir = if isDir then file else builtins.dirOf file;
                  in
                  underDir currentDir i
                else
                  false;
            in
            if shouldWrap then wrapNormalModule false moduleInfo i else i
          ) originalImports;
        in
        {
          imports = wrappedImports;
          options = finalOpts;
          config = lib.mkIf mkIfCondition mergedConfig;
        };

      # Functor 包装
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

  # wrapNormalModule :: Bool -> ModuleInfo -> (Path | Module) -> Module
  # 用于递归包装本地 imports
  wrapNormalModule =
    injectEnable: moduleInfo: module:
    genericWrapModule {
      inherit injectEnable;
      checkStrictOptions = false;
    } moduleInfo module;

  # ================================================================
  # 3. Specialized Wrappers
  # ================================================================

  # wrapGuardedOptions :: GuardedTree -> Module
  # 包装 guarded 模块的 options.nix
  wrapGuardedOptions =
    tree:
    let
      moduleInfo = {
        modPath = tree.modPath;
        path = tree.path;
        kind = "directory";
        hasOptions = true;
        hasDefault = false;
        moduleType = "guarded";
        inherit (tree) parentGuardedPaths;
      };
    in
    genericWrapModule {
      injectEnable = true;
      checkStrictOptions = false; # 暂时禁用 strict mode 检查
    } moduleInfo (tree.path + "/options.nix");

  # wrapGuardedConfig :: GuardedTree -> Module
  # 包装 guarded 模块的配置文件
  wrapGuardedConfig =
    tree:
    let
      moduleInfo = {
        modPath = tree.modPath;
        path = tree.path;
        kind = "directory";
        hasOptions = true;
        hasDefault = false;
        moduleType = "guarded";
        inherit (tree) parentGuardedPaths;
      };

      # Enable 检查路径: 所有父级 guarded 路径 + 自身路径
      # 用于生成 mkIf 条件
      allGuardedPaths = tree.parentGuardedPaths ++ [ tree.modPath ];
      enableCheckPath = map (p: p ++ [ "enable" ]) allGuardedPaths;

      wrapFile =
        filePath:
        genericWrapModule {
          injectEnable = false;
          checkStrictOptions = false;
          inherit enableCheckPath;
        } moduleInfo filePath;
    in
    {
      key = toString tree.path + "/config";
      imports = map wrapFile tree.unguardedFiles;
    };

  # wrapGuardedModule :: GuardedTree -> Module
  # 包装完整的 guarded 模块 (options + config)
  wrapGuardedModule = tree: {
    key = toString tree.path;
    imports = [
      (wrapGuardedOptions tree)
      (wrapGuardedConfig tree)
    ];
  };

  # wrapTraditionalModule :: ModuleInfo -> Module
  # 包装传统目录模块
  wrapTraditionalModule =
    moduleInfo:
    genericWrapModule {
      injectEnable = false;
      checkStrictOptions = false;
    } moduleInfo (moduleInfo.path + "/default.nix");

  # wrapSingleModule :: ModuleInfo -> Module
  # 包装单文件模块
  wrapSingleModule =
    moduleInfo:
    genericWrapModule {
      injectEnable = false;
      checkStrictOptions = false;
    } moduleInfo moduleInfo.path;

  # ================================================================
  # 4. Module Collection
  # ================================================================

  # collectModules :: Path -> String -> [ModuleInfo]
  # 收集所有三种类型的模块
  collectModules =
    root: suffix:
    let
      # 1. 构建 guarded 树
      guardedTree = mkGuardedTree root suffix;

      # 2. 收集所有 guarded 节点 (递归)
      collectGuardedNodes = tree: [ tree ] ++ concatLists (map collectGuardedNodes tree.guardedChildren);

      allGuardedNodes = collectGuardedNodes guardedTree;

      # 转换 guarded 树为 ModuleInfo
      guardedModuleInfos = map (tree: {
        modPath = tree.modPath;
        path = tree.path;
        moduleType = "guarded";
        kind = "directory";
        hasOptions = true;
        hasDefault = false;
        inherit (tree) unguardedFiles parentGuardedPaths;
      }) (lib.filter (t: t.modPath != [ ]) allGuardedNodes);

      # 3. 收集传统和单文件模块
      # 注意: 只包含实际的 guarded 模块路径 (排除根节点，因为根节点 modPath = [])
      guardedPaths = map (t: t.path) (lib.filter (t: t.modPath != [ ]) allGuardedNodes);

      # 根据路径在 guarded 树中查找对应的树节点
      findTreeByPath =
        tree: targetPath:
        if tree.path == targetPath then
          tree
        else
          lib.findFirst (t: t != null) null (
            map (child: findTreeByPath child targetPath) tree.guardedChildren
          );

      scanOthers =
        path: breadcrumbs:
        let
          files = lsFiles path;
          dirs = lib.lsDirs path;

          hasDefault = elem "default.nix" files;
          isGuarded = elem path guardedPaths;

          # 传统模块
          traditional =
            if !isGuarded && hasDefault then
              [
                {
                  modPath = breadcrumbs;
                  path = path;
                  moduleType = "traditional";
                  kind = "directory";
                  hasOptions = false;
                  hasDefault = true;
                  unguardedFiles = [ ];
                  parentGuardedPaths = [ ];
                }
              ]
            else
              [ ];

          # 单文件模块 - 使用配置的 suffix 过滤
          single =
            if !isGuarded && !hasDefault then
              forFilter files (
                f:
                if hasSuffix suffix f then
                  let
                    name = lib.removeSuffix suffix f;
                  in
                  {
                    modPath = breadcrumbs ++ [ name ];
                    path = path + "/${f}";
                    moduleType = "single";
                    kind = "file";
                    hasOptions = false;
                    hasDefault = false;
                    unguardedFiles = [ ];
                    parentGuardedPaths = [ ];
                  }
                else
                  null
              )
            else
              [ ];

          # 递归子目录
          # 注意: 传统模块不支持嵌套 - scanOthers 会在有 default.nix 的目录停止进一步递归
          # 但我们仍需要调用 scanOthers 来收集传统模块本身
          subResults = concatLists (
            map (
              d:
              let
                subPath = path + "/${d}";
                isSubGuarded = elem subPath guardedPaths;
              in
              # 跳过 guarded 子目录 (由 guarded 模块系统单独处理)
              if !isSubGuarded then scanOthers subPath (breadcrumbs ++ [ d ]) else [ ]
            ) dirs
          );
        in
        traditional ++ single ++ subResults;

      otherModuleInfos = scanOthers root [ ];
    in
    guardedModuleInfos ++ otherModuleInfos;

  # wrapModule :: Path -> ModuleInfo -> Module
  # 根据模块类型包装模块
  wrapModule =
    guardedTree: moduleInfo:
    if moduleInfo.moduleType == "guarded" then
      # 需要重建 GuardedTree 用于 guarded 模块
      let
        tree = findTreeByPathDeep guardedTree moduleInfo.path;
        findTreeByPathDeep =
          tree: targetPath:
          if tree.path == targetPath then
            tree
          else
            lib.findFirst (t: t != null) null (
              map (child: findTreeByPathDeep child targetPath) tree.guardedChildren
            );
      in
      if tree != null then
        wrapGuardedModule tree
      else
        throw "Cannot find guarded tree for ${toString moduleInfo.path}"
    else if moduleInfo.moduleType == "traditional" then
      wrapTraditionalModule moduleInfo
    # single
    else
      wrapSingleModule moduleInfo;

  # ================================================================
  # 5. Output Generation
  # ================================================================

  # mkModulesOutputSingle :: Path -> String -> { modules :: [{ name :: String, value :: Module }], default :: Module }
  # 为单个目录生成模块输出
  mkModulesOutputSingle =
    modulesDir: suffix:
    let
      guardedTree = mkGuardedTree modulesDir suffix;
      moduleInfos = collectModules modulesDir suffix;

      # 生成独立模块输出
      # 使用 "/" 作为路径分隔符，避免与 Nix 属性路径的点号混淆
      modules = map (info: {
        name = concatStringsSep "/" info.modPath;
        value = wrapModule guardedTree info;
      }) moduleInfos;

      # default 模块 - 引入所有模块
      defaultModule = {
        key = toString modulesDir + ":default";
        imports = map (m: m.value) modules;
      };
    in
    {
      inherit modules;
      default = defaultModule;
    };

  # mkModulesOutput :: { moduleDirs :: [Path], suffix :: String } -> { nixosModules :: AttrSet }
  # 为多个目录生成模块输出
  mkModulesOutput =
    { moduleDirs, suffix }:
    let
      # 收集所有目录的模块
      allOutputs = map (dir: mkModulesOutputSingle dir suffix) moduleDirs;

      # 合并所有模块
      allModules = concatLists (map (o: o.modules) allOutputs);

      # 检测重复的模块名
      moduleNames = map (m: m.name) allModules;
      _ =
        let
          duplicates = lib.filter (name: lib.count (n: n == name) moduleNames > 1) (lib.unique moduleNames);
        in
        if lib.length duplicates > 0 then
          throw "Duplicate module names found: ${concatStringsSep ", " duplicates}"
        else
          null;

      # default 模块 - 引入所有模块
      defaultModule = {
        key = "default";
        imports = map (m: m.value) allModules;
      };
    in
    {
      nixosModules =
        listToAttrs allModules
        // (
          if allModules == [ ] then
            { }
          else
            {
              default = defaultModule;
            }
        );
    };

in
{
  inherit
    mkGuardedTree
    mkGuardedTreeNode
    genericWrapModule
    wrapGuardedOptions
    wrapGuardedConfig
    wrapGuardedModule
    wrapTraditionalModule
    wrapSingleModule
    wrapNormalModule
    collectModules
    wrapModule
    mkModulesOutputSingle
    mkModulesOutput
    ;
}
