# Module System Guide

This document provides detailed guidance on using the flake-fhs module system.

## Overview

The flake-fhs module system automatically discovers and loads NixOS modules from your directory structure. It supports **three mutually exclusive module types**:

1. **Guarded Directory Module** - For optional features with enable/disable control
2. **Traditional Directory Module** - For configuration sets that are always active
3. **Single File Module** - For simple modules

## Module Types in Detail

### 1. Guarded Directory Module

**Identifier**: Directory contains `options.nix` (without `default.nix`)

**Features**:
- Auto-generates `enable` option
- Config files (matching suffix) are **recursively collected** from:
  - Current directory
  - All non-guarded subdirectories (regardless of `default.nix` presence)
- All config files wrapped with `mkIf enable`
- Supports nesting with parent enable checks

**Directory Structure**:
```
modules/
└── my-feature/
    ├── options.nix    # Required: option definitions
    ├── config.nix     # Optional: configuration (wrapped with mkIf)
    └── sub-feature/   # Optional: subdirectory without options.nix
        └── setup.nix  # Also collected and wrapped with mkIf
```

**Example `options.nix`**:
```nix
{ lib, ... }:
{
  options.my-feature = {
    setting1 = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "A configurable setting";
    };
  };
}
```

**Example `config.nix`**:
```nix
{ config, ... }:
{
  config.my-feature.result = config.my-feature.setting1;
}
```

**Generated Output**:
- `nixosModules.my-feature` - Complete module with options and config
- Enable option: `my-feature.enable` (auto-generated if not defined)

**Usage**:
```nix
# In your NixOS configuration
{ config, ... }:
{
  imports = [ flake.nixosModules.my-feature ];
  
  my-feature = {
    enable = true;  # Must be enabled for config to apply
    setting1 = "custom-value";
  };
}
```

#### Custom File Suffix

By default, guarded modules auto-discover and import `.nix` files (excluding `options.nix` and `scope.nix`). You can customize this suffix in your flake.nix:

```nix
{
  outputs = inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      layout.nixosModules = {
        subdirs = [ "modules" ];
        suffix = ".mod.nix";  # Only import files ending with .mod.nix
      };
    };
}
```

With this configuration, only files matching the suffix will be auto-imported:

```
modules/
└── my-feature/
    ├── options.nix      # Required: option definitions
    ├── config.mod.nix   # ✅ Imported (matches suffix)
    ├── setup.mod.nix    # ✅ Imported (matches suffix)
    └── helper.nix       # ❌ NOT imported (doesn't match suffix)
```

This is useful when you want to:
- Keep helper/internal `.nix` files that shouldn't be auto-imported
- Use a naming convention to distinguish config files from other files

### 2. Traditional Directory Module

**Identifier**: Directory contains `default.nix` (without `options.nix`)

**Features**:
- Direct export, always active
- No enable mechanism
- Does NOT support nesting (subdirs with `default.nix` are ignored)

**Directory Structure**:
```
modules/
└── my-configs/
    └── default.nix   # Required: module definition
```

**Example `default.nix`**:
```nix
{ lib, ... }:
{
  options.my-configs = {
    value1 = lib.mkOption {
      type = lib.types.int;
      default = 42;
    };
  };
  
  config.my-configs = {
    active = true;
  };
}
```

**Generated Output**:
- `nixosModules.my-configs` - Complete module, always applied

**Usage**:
```nix
# In your NixOS configuration
{ config, ... }:
{
  imports = [ flake.nixosModules.my-configs ];
  
  # Config is always applied, no enable needed
  my-configs.value1 = 100;
}
```

### 3. Single File Module

**Identifier**: Standalone file matching the configured suffix (default: `.nix`) in modules directory

**Features**:
- Direct export, always active
- No enable mechanism
- Found recursively in non-guarded, non-traditional directories
- File suffix is configurable via `layout.nixosModules.suffix`

**Directory Structure** (with default suffix `.nix`):
```
modules/
├── utils.nix          # Single file module
└── helpers/
    └── common.nix     # Also a single file module
```

**Directory Structure** (with custom suffix `.mod.nix`):
```
modules/
├── utils.mod.nix      # Single file module
├── helper.nix         # ❌ NOT recognized (doesn't match suffix)
└── helpers/
    └── common.mod.nix # Single file module
```

**Example `utils.nix`**:
```nix
{ lib, ... }:
{
  options.utils = {
    enabled = lib.mkEnableOption "utils feature";
  };
  
  config.utils = {
    active = true;
  };
}
```

**Generated Outputs**:
- `nixosModules.utils`
- `nixosModules.helpers.common`

## Nested Guarded Modules

Guarded modules can be nested. Child modules check **ALL** parent enables:

```
modules/
└── network/              # network.enable
    ├── options.nix
    ├── config.nix
    └── services/
        └── web/          # network.enable && network.services.web.enable
            ├── options.nix
            └── config.nix
```

**Generated mkIf conditions**:
- `network/config.nix`: `lib.mkIf config.network.enable { ... }`
- `network/services/web/config.nix`: `lib.mkIf (config.network.enable && config.network.services.web.enable) { ... }`

**Example**:
```nix
{ config, ... }:
{
  imports = [ flake.nixosModules.default ];
  
  network = {
    enable = true;  # Parent must be enabled
    services.web = {
      enable = true;  # Child must also be enabled
      port = 8080;
    };
  };
}
```

## Conflict Detection

**Important**: A directory cannot have both `options.nix` and `default.nix`. This will cause a build error:

```
modules/
└── conflict/
    ├── options.nix   # ❌
    └── default.nix   # ❌ CONFLICT!
```

**Error Message**:
```
Conflict in /path/to/modules/conflict: Cannot have both options.nix and default.nix.
Choose one module type: guarded (options.nix only) or traditional (default.nix only).
```

## Traditional Module Nesting Limitation

Traditional modules **do NOT support nesting**. Subdirectories with `default.nix` are ignored:

```
modules/
└── configs/
    ├── default.nix       # ✅ Recognized: nixosModules.configs
    └── sub/
        └── default.nix   # ❌ NOT recognized (skipped)
```

**Solution**: Use guarded modules for nesting, or create separate top-level modules:
```
modules/
├── configs/              # Traditional module
│   └── default.nix
└── configs-sub/          # Separate traditional module
    └── default.nix
```

## Strict Options Validation

By default, option namespace is not enforced. You can enable strict validation:

```nix
{
  outputs = inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      layout.nixosModules.strictOptions = true;
    };
}
```

When enabled, each option's namespace must match its directory path:

```nix
# modules/foo/options.nix
{ lib, ... }:
{
  options.foo = {  # Must be under 'foo'
    setting = lib.mkOption { ... };
  };
}

# modules/foo/bar/options.nix
{ lib, ... }:
{
  options.foo.bar = {  # Must be under 'foo.bar'
    setting = lib.mkOption { ... };
  };
}
```

Violations are reported via `config.assertions` at system evaluation time, using post-evaluation declaration tracking from the NixOS module system.

## Output Structure

### Individual Module Outputs
Each module generates a single output at `nixosModules.<path>`:

| Directory | Output |
|-----------|--------|
| `modules/myapp/` | `nixosModules.myapp` |
| `modules/services/web/` | `nixosModules.services.web` |
| `modules/utils.nix` | `nixosModules.utils` |

### Default Module
`nixosModules.default` includes ALL modules:
- All guarded modules (with enable guards)
- All traditional modules (always active)
- All single file modules (always active)

```nix
# Import all modules at once
{ ... }:
{
  imports = [ flake.nixosModules.default ];
  
  # Enable guarded modules as needed
  myapp.enable = true;
  services.web.enable = true;
}
```

## Migration from Previous Versions

### From options.nix + default.nix to Guarded Module
**Before**:
```
modules/myapp/
├── options.nix
└── default.nix
```

**After** (rename `default.nix` to `config.nix`):
```
modules/myapp/
├── options.nix
└── config.nix
```

### From Separate .options/.config to Single Output
**Before**:
```nix
imports = [ flake.nixosModules.myapp.options ];
```

**After**:
```nix
imports = [ flake.nixosModules.myapp ];  # Merged output
```

### From optionsMode Configuration
The old `optionsMode` configuration (auto/strict/free) has been replaced by `layout.nixosModules.strictOptions` (default: `false`). Enable it to validate option namespace alignment with directory structure.

### From Nested Traditional Modules
**Before** (sub-modules were recognized):
```
modules/
└── configs/
    ├── default.nix      # nixosModules.configs
    └── sub/
        └── default.nix  # nixosModules.configs.sub
```

**After** (sub-modules are NOT recognized):
- Use guarded modules for nesting
- Or create separate top-level modules
