# Module System Refactor Design

> **Status: Implemented.** This document records the design rationale for the module system refactor. The implementation lives in `lib/fhs-modules.nix`. See `docs/manual-modules.md` for the user-facing guide.

## Overview

This document describes the redesigned module system for flake-fhs, combining the best ideas from both `master` and `feature-refactor-modules` branches.

## Design Goals

1. **Clear Conceptual Model**: Three mutually exclusive module types
2. **User-Friendly**: Traditional modules require zero learning
3. **Maintainable**: SSOT design with clear responsibilities
4. **Simplified**: Remove unnecessary complexity (optionsMode, partial loading)

---

## 1. Module Taxonomy

### 1.1 Three Module Types

```
Module Types (Mutually Exclusive)
│
├─ Guarded Directory Module
│  ├─ Identifier: Directory contains options.nix
│  ├─ Features:
│  │  ├─ Auto-generates enable option
│  │  ├─ Config files wrapped with mkIf enable
│  │  └─ Nested modules check ALL parent enables
│  ├─ Constraints: Cannot have default.nix (conflict error)
│  └─ Use Case: Optional feature modules
│
├─ Traditional Directory Module
│  ├─ Identifier: Directory contains default.nix (no options.nix)
│  ├─ Features: Direct export, no enable mechanism
│  ├─ Constraints: No nesting (subdirs with default.nix are NOT recognized)
│  └─ Use Case: Configuration sets, complex modules
│
└─ Single File Module
   ├─ Identifier: Standalone .nix file
   ├─ Features: Direct export, no enable mechanism
   └─ Use Case: Simple modules
```

### 1.2 Design Decisions

**Q1: How to handle unguarded directories?**
- **Decision**: Recursively collect and export as single file modules
- **Rationale**: Clear semantics, no hidden behavior

**Q2: What should nixosModules.default include?**
- **Decision**: Include all modules (guarded, traditional, single)
- **Rationale**: Zero-boilerplate philosophy

**Q3: Can options.nix and default.nix coexist?**
- **Decision**: No, throw conflict error
- **Rationale**: Prevent ambiguity, force clear module type

**Q4: Support partial loading?**
- **Decision**: No, too complex for current needs
- **Rationale**: All modules in nixosModules.default is simpler

**Q5: Keep optionsMode?**
- **Decision**: No, only strict mode
- **Rationale**: Simplify implementation, remove config parameter

**Q6: Can Traditional Directory Modules nest?**
- **Decision**: No, subdirectories with default.nix are not recognized as modules
- **Rationale**: 
  - Traditional modules are "encapsulated" - they manage their own imports
  - Prevents confusion about module boundaries
  - If nesting is needed, use guarded modules instead
  - Simplifies implementation and mental model

---

## 2. Data Structures

### 2.1 Core Types

```nix
# type ModPath = [String]
#   Module path segments, e.g., ["services" "web-server"]

# type ModuleType = "guarded" | "traditional" | "single"

# type GuardedPath = [String]
#   Path to a guarded module's enable option

# type GuardedTree = {
#   modPath :: ModPath;
#   path :: Path;
#   parentGuardedPaths :: [GuardedPath];  # Parent guarded paths for nested mkIf
#   fullGuardedPath :: GuardedPath;       # Full path including self
#   files :: [String];
#   unguardedFiles :: [Path];
#   guardedChildren :: [GuardedTree];
# }

# type ModuleInfo = {
#   modPath :: ModPath;
#   path :: Path;
#   moduleType :: ModuleType;
#   kind :: "file" | "directory";
#   hasOptions :: Bool;
#   hasDefault :: Bool;
#   unguardedFiles :: [Path];        # For guarded modules
#   parentGuardedPaths :: [GuardedPath];  # For nested mkIf
# }
```

### 2.2 Nested Guarded Modules

When guarded modules are nested, child modules' configs check ALL parent enables:

```
Example:
modules/
└── network/              # network.enable
    ├── options.nix
    ├── config.nix
    └── services/
        └── web/          # network.enable && network.services.web.enable
            ├── options.nix
            └── config.nix
```

Generated mkIf conditions:
- `network/config.nix`: `lib.mkIf config.network.enable { ... }`
- `network/services/web/config.nix`: `lib.mkIf (config.network.enable && config.network.services.web.enable) { ... }`

### 2.3 Traditional Module Boundary

Traditional Directory Modules are **encapsulated** - they do not support nesting:

```
Example:
modules/
└── configs/
    ├── default.nix       # Recognized as traditional module: nixosModules.configs
    ├── utils.nix         # Imported by configs/default.nix (if it imports it)
    └── sub/
        └── default.nix   # NOT recognized (skipped during collection)
```

**Rationale:**
- Traditional modules manage their own imports explicitly
- Prevents ambiguous module boundaries
- If nesting is needed, use guarded modules instead
- Simpler mental model: traditional = encapsulated, guarded = nestable

---

## 3. Core Implementation

### 3.1 mkGuardedTree - SSOT for Guarded Modules

**Responsibility**: Single source of truth for guarded module identification and nesting.

```nix
# mkGuardedTreeNode :: { modPath, path, parentGuardedPaths } -> GuardedTree
mkGuardedTreeNode =
  { modPath, path, parentGuardedPaths }:
  let
    files = lsFiles path;
    hasOptions = elem "options.nix" files;
    hasDefault = elem "default.nix" files;
    
    # Conflict detection
    _ = 
      if hasOptions && hasDefault then
        throw "Conflict in ${toString path}: Cannot have both options.nix and default.nix"
      else null;
    
    # Collect unguarded files (for guarded modules without default.nix)
    unguardedFiles =
      if hasOptions && !hasDefault then
        forFilter files (
          f: 
          if hasSuffix ".nix" f && f != "options.nix" && f != "scope.nix" then
            path + "/${f}"
          else
            null
        )
      else
        [ ];
    
    # Full guarded path (including self)
    fullGuardedPath = parentGuardedPaths ++ [ modPath ];
    
    # Recursively process subdirectories
    guardedChildren = 
      concatLists (
        exploreDir [ path ] (it: rec {
          options-dot-nix = it.path + "/options.nix";
          default-dot-nix = it.path + "/default.nix";
          guarded = pathExists options-dot-nix;
          defaulted = pathExists default-dot-nix;
          
          # Enter non-guarded, non-defaulted directories
          into = !(guarded || defaulted);
          # Collect guarded directories
          pick = guarded;
          
          out = mkGuardedTreeNode {
            modPath = modPath ++ [ it.name ];
            path = it.path;
            # Pass updated parent guarded paths to children
            parentGuardedPaths = 
              if hasOptions then fullGuardedPath
              else parentGuardedPaths;
          };
        })
      );
  in
  {
    inherit modPath path files unguardedFiles guardedChildren;
    inherit parentGuardedPaths fullGuardedPath;
  };

# mkGuardedTree :: Path -> GuardedTree
mkGuardedTree = root:
  mkGuardedTreeNode {
    modPath = [ ];
    path = root;
    parentGuardedPaths = [ ];
  };
```

---

### 3.2 Module Wrappers (Based on feature-refactor-modules)

**Design Philosophy**: Unified wrapper engine with configurable strategies.

#### 3.2.1 Generic Wrapper Engine

```nix
# genericWrapModule :: {
#   injectEnable :: Bool,
#   checkStrictOptions :: Bool,
#   enableCheckPath :: [GuardedPath]?
# } -> ModuleInfo -> (Path | Module) -> Module
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
    isDir = if isPath then isDirectory module else false;
    
    raw =
      if isPath then
        if isDir then import module
        else if isEmptyFile module then { }
        else import module
      else
        module;

    # Strict mode validation
    checkStrict = opts: path:
      if opts == { } || path == [ ] then true
      else
        let h = head path;
        in
        if hasAttr h opts && removeAttrs opts [ h ] == { } then
          checkStrict opts.${h} (tail path)
        else
          false;

    # Transform module content
    transform = content:
      { config, lib, ... }:
      let
        opts = content.options or { };
        
        # 1. Strict validation
        _ =
          if checkStrictOptions && !checkStrict opts modPath then
            throw "Strict mode violation: options in ${toString file} must follow ${concatStringsSep "." modPath}"
          else null;
        
        # 2. Enable option injection
        enablePath = modPath ++ [ "enable" ];
        finalOpts =
          if injectEnable && !lib.hasAttrByPath enablePath opts then
            lib.recursiveUpdate opts (
              lib.setAttrByPath modPath {
                enable = lib.mkEnableOption (concatStringsSep "." modPath);
              }
            )
          else opts;
        
        # 3. Config merging
        explicitConfig = content.config or { };
        implicitConfig = removeAttrs content [
          "imports" "options" "config" "_file" "meta" 
          "disabledModules" "__functor" "__functionArgs"
        ];
        mergedConfig = lib.mkMerge [ explicitConfig implicitConfig ];
        
        # 4. mkIf condition (for nested guarded modules)
        mkIfCondition =
          if enableCheckPath != null then
            # Nested: check ALL parent enables AND self
            let
              allEnablePaths = enableCheckPath ++ [ modPath ++ [ "enable" ] ];
              conditions = map (path: lib.attrsets.getAttrFromPath path config) allEnablePaths;
            in
            foldl' (acc: cond: acc && cond) true conditions
          else if injectEnable then
            # Top-level: just check self
            lib.attrsets.getAttrFromPath enablePath config
          else
            true;  # No enable check
        
        # 5. Recursive wrapping of local imports
        originalImports = content.imports or [ ];
        wrappedImports = map (
          i:
          let
            isPathOrString = builtins.isPath i || builtins.isString i;
            shouldWrap =
              if isPathOrString && file != null then
                let currentDir = if isDir then file else builtins.dirOf file;
                in underDir currentDir i
              else false;
          in
          if shouldWrap then wrapNormalModule false moduleInfo i else i
        ) originalImports;
      in
      {
        imports = wrappedImports;
        options = finalOpts;
        config = lib.mkIf mkIfCondition mergedConfig;
      };

    # Functor wrapper
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
```

#### 3.2.2 Specialized Wrappers

```nix
# wrapGuardedOptions :: GuardedTree -> Module
wrapGuardedOptions = tree:
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
    checkStrictOptions = true;
  } moduleInfo (tree.path + "/options.nix");

# wrapGuardedConfig :: GuardedTree -> Module
wrapGuardedConfig = tree:
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
    
    # Enable check path: all parent guarded paths
    enableCheckPath = 
      if tree.parentGuardedPaths != [ ] then
        map (p: p ++ [ "enable" ]) tree.parentGuardedPaths
      else
        null;
    
    wrapFile = filePath:
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
wrapGuardedModule = tree:
  {
    key = toString tree.path;
    imports = [
      (wrapGuardedOptions tree)
      (wrapGuardedConfig tree)
    ];
  };

# wrapTraditionalModule :: ModuleInfo -> Module
wrapTraditionalModule = moduleInfo:
  genericWrapModule {
    injectEnable = false;
    checkStrictOptions = false;
  } moduleInfo (moduleInfo.path + "/default.nix");

# wrapSingleModule :: ModuleInfo -> Module
wrapSingleModule = moduleInfo:
  genericWrapModule {
    injectEnable = false;
    checkStrictOptions = false;
  } moduleInfo moduleInfo.path;

# wrapNormalModule :: Bool -> ModuleInfo -> (Path | Module) -> Module
# For recursive wrapping of local imports
wrapNormalModule = injectEnable: moduleInfo: module:
  genericWrapModule {
    inherit injectEnable;
    checkStrictOptions = false;
  } moduleInfo module;
```

---

### 3.3 Module Collection

**Design**: Unified collection returning `[ModuleInfo]` with moduleType field.

```nix
# collectModules :: Path -> [ModuleInfo]
collectModules = root:
  let
    # 1. Build guarded tree
    guardedTree = mkGuardedTree root;
    
    # 2. Collect all guarded nodes (recursive)
    collectGuardedNodes = tree:
      [ tree ] ++ concatLists (map collectGuardedNodes tree.guardedChildren);
    
    allGuardedNodes = collectGuardedNodes guardedTree;
    
    # Convert guarded trees to ModuleInfo
    guardedModuleInfos = 
      map (tree: {
        modPath = tree.modPath;
        path = tree.path;
        moduleType = "guarded";
        kind = "directory";
        hasOptions = true;
        hasDefault = false;
        inherit (tree) unguardedFiles parentGuardedPaths;
      }) (filter (t: t.modPath != [ ]) allGuardedNodes);
    
    # 3. Collect traditional and single modules
    guardedPaths = map (t: t.path) allGuardedNodes;
    
    scanOthers = path: breadcrumbs:
      let
        files = lsFiles path;
        dirs = lsDirs path;
        
        hasDefault = elem "default.nix" files;
        isGuarded = elem path guardedPaths;
        
        # Traditional module
        traditional =
          if !isGuarded && hasDefault then
            [ {
              modPath = breadcrumbs;
              path = path;
              moduleType = "traditional";
              kind = "directory";
              hasOptions = false;
              hasDefault = true;
              unguardedFiles = [ ];
              parentGuardedPaths = [ ];
            } ]
          else [ ];
        
        # Single file modules
        single =
          if !isGuarded && !hasDefault then
            forFilter files (
              f:
              if hasSuffix ".nix" f then
                let name = removeSuffix ".nix" f;
                in [ {
                  modPath = breadcrumbs ++ [ name ];
                  path = path + "/${f}";
                  moduleType = "single";
                  kind = "file";
                  hasOptions = false;
                  hasDefault = false;
                  unguardedFiles = [ ];
                  parentGuardedPaths = [ ];
                } ]
              else null
            )
          else [ ];
        
        # Recurse subdirectories
        # Note: Traditional modules do NOT nest - subdirs with default.nix are skipped
        # This maintains clear module boundaries and simplifies the mental model
        subResults = concatLists (map (d:
          let
            subPath = path + "/${d}";
            isSubGuarded = elem subPath guardedPaths;
            hasSubDefault = builtins.pathExists (subPath + "/default.nix");
          in
          # Skip subdirectories with default.nix (traditional modules don't nest)
          if !isSubGuarded && !hasSubDefault then
            scanOthers subPath (breadcrumbs ++ [ d ])
          else [ ]
        ) dirs);
      in
        traditional ++ single ++ subResults;
    
    otherModuleInfos = scanOthers root [ ];
  in
    guardedModuleInfos ++ otherModuleInfos;

# wrapModule :: ModuleInfo -> Module
wrapModule = moduleInfo:
  if moduleInfo.moduleType == "guarded" then
    # Need to reconstruct GuardedTree for guarded modules
    let
      tree = findTreeByPath guardedTree moduleInfo.path;
    in
    wrapGuardedModule tree
  else if moduleInfo.moduleType == "traditional" then
    wrapTraditionalModule moduleInfo
  else  # single
    wrapSingleModule moduleInfo;
```

---

### 3.4 Output Generation

```nix
# mkModulesOutput :: Path -> { nixosModules :: AttrSet }
mkModulesOutput = modulesDir:
  let
    moduleInfos = collectModules modulesDir;
    
    # Generate individual module outputs
    modules = map (info: {
      name = concatStringsSep "." info.modPath;
      value = wrapModule info;
    }) moduleInfos;
    
    # nixosModules.default - Import all modules
    defaultModule = {
      key = "default";
      imports = map (m: m.value) modules;
    };
  in
  {
    nixosModules = listToAttrs modules // {
      default = defaultModule;
    };
  };
```

---

## 4. Implementation Checklist

All items completed. Core files modified:
- `lib/fhs-modules.nix` — Main implementation
- `lib/fhs-config.nix` — Configuration options
- `lib/file.nix` — Utility functions

Tests created:
- `checks/guarded-basic.nix`, `checks/guarded-nested.nix`, `checks/guarded-merge.nix`, `checks/guarded-tree-structure.nix`
- `checks/traditional-basic.nix`
- `checks/single-file.nix`
- `checks/conflict-detection.nix`
- `checks/module-collection.nix`, `checks/module-custom-suffix.nix`
- `checks/no-modules-output.nix`
- `checks/strict-options.nix`

---

## 5. Breaking Changes & Migration

### 5.1 Breaking Changes

1. **options.nix + default.nix Conflict**
   - Before: Allowed
   - After: Error
   - Migration: Choose one or restructure

2. **No .options and .config outputs**
   - Before: Separate outputs
   - After: Single merged output
   - Migration: Use single module name

3. **optionsMode removed**
   - Before: auto/strict/free
   - After: strict only
   - Migration: Ensure options match directory structure

4. **No partial loading**
   - Before: Could load modules selectively
   - After: All modules in default
   - Migration: Use individual module outputs if needed

5. **Traditional modules don't nest**
   - Before: Subdirs with default.nix were also recognized
   - After: Only top-level traditional module is recognized
   - Migration: Use guarded modules or restructure directory

### 5.2 Migration Guide

```markdown
# Migration from master to new design

## Case 1: Guarded module with default.nix
Before:
```
modules/myapp/
├── options.nix
└── default.nix
```

After (Option A - Auto-discovery):
```
modules/myapp/
├── options.nix
└── config.nix  # Renamed from default.nix
```

After (Option B - Traditional module):
```
modules/myapp/
└── default.nix  # Removed options.nix
```

## Case 2: Accessing .options and .config
Before:
```nix
imports = [ flake.nixosModules.myapp.options ];
```

After:
```nix
imports = [ flake.nixosModules.myapp ];  # Merged
```

## Case 3: Nested traditional modules
**Not supported**: Traditional modules do not nest

Example that WON'T work:
```
modules/
└── configs/
    ├── default.nix      # Recognized as traditional module
    └── sub/
        └── default.nix  # NOT recognized (skipped)
```

Solution: Use guarded modules for nesting, or restructure:
```
modules/
├── configs/             # Traditional module
│   └── default.nix
└── configs-sub/         # Separate traditional module
    └── default.nix
```
```
