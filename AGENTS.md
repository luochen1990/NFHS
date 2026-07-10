# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Flake FHS** (Flake Flake Hierarchy Standard) is a framework for Nix flakes that automatically generates flake outputs from a standardized directory structure, eliminating the need to write repetitive `flake.nix` boilerplate code.

## Core Architecture

### Directory Mapping System

The framework implements an automatic mapping from directory structure to flake outputs:

| Subdirectories (Aliases) | File Pattern | Special Files | Recursive | Generated Output | Nix Command |
|---|---|---|:---:|---|---|
| `packages` (`pkgs`) | `<name>.nix` or `<name>/package.nix` | `scope.nix` | ✅ | `packages.<system>.<name>` | `nix build .#<name>` |
| `nixosModules` (`modules`) | `<name>/...` | `options.nix`, `default.nix` | ✅ | `nixosModules.<name>` | - |
| `nixosConfigurations` (`hosts`) | `<name>/configuration.nix` | `default.nix` | ✅ | `nixosConfigurations.<name>` | `nixos-rebuild --flake .#<name>` |
| `apps` | `<name>.nix` or `<name>/package.nix` | `scope.nix` | ✅ | `apps.<system>.<name>` | `nix run .#<name>` |
| `devShells` (`shells`) | `<name>.nix` | `default.nix` | ✅ | `devShells.<system>.<name>` | `nix develop .#<name>` |
| `templates` | `<name>/` | `flake.nix` | ❌ | `templates.<name>` | `nix flake init --template <url>#<name>` |
| `lib` | `<name>.nix` | - | ✅ | `lib.<name>` | `nix eval .#lib.<name>` |
| `checks` | `<name>.nix` or `<name>/package.nix` | `scope.nix` | ✅ | `checks.<system>.<name>` | `nix flake check .#<name>` |

### Host Metadata (nixosConfigurations)

Host directories can contain a `default.nix` file that exports host-specific metadata. This is evaluated before NixOS modules to configure the globally shared `pkgs` instance accurately for that host.

```nix
# hosts/my-host/default.nix
{
  system = "x86_64-linux";
  nixpkgs = {
    config = { allowUnfree = true; cudaSupport = true; };
    overlays = [ /* overlays */ ];
  };
}
```

### Unified Package Model

The framework unifies the handling of `packages`, `apps`, and `checks` under a single **"Scoped Package Tree"** model.

- **Unified Entry**: Supports both single-file (`<name>.nix`) and directory-based (`<name>/package.nix`) definitions.
- **Encapsulation**: If a directory contains `package.nix`, it is treated exclusively as a package definition. Other `.nix` files in that directory are ignored by the automatic scanner (treated as internal helper files).
- **Unified Build**: All components are built using `callPackage`, enjoying automatic dependency injection from `pkgs`.
- **Unified Scoping**: `scope.nix` is supported in all hierarchies (`pkgs`, `apps`, `checks`) to customize dependencies or inject parameters.
- **Explicit Context**: The `scope.nix` function receives the full system context (`pkgs`, `self`, `inputs`, `system`, `lib`) as arguments, allowing users to explicitly inject them into the package scope if desired. Auto-injection is avoided to keep the default scope clean.

### Specific Behaviors

- **Apps**: Automatically converts the built package into an App structure (`{ type="app"; program="..."; }`) by inferring the main program (via `meta.mainProgram` or package name).
- **Checks**: Treated as packages that run tests during build. Access to `self` or `inputs` is available via function arguments.

### Package Scope System (callPackage)

The framework uses `callPackage` to build packages. You can customize the `callPackage` context (scope) via `scope.nix`.

- **File**: `<dir>/scope.nix` (Applies to current directory and subdirectories)
- **Mechanism**:
  - `package.nix` is built using `currentScope.callPackage`.
  - `scope.nix` modifies `currentScope` for its directory (and children).
- **Signature**: `{ pkgs, inputs, ... }: { scope = ...; args = ...; }`
  - **scope** (Optional): The base package set (e.g., `pkgs.pythonPackages`) to use for `callPackage`.
    - If provided: **Replaces** the parent scope.
    - If omitted: **Inherits** the parent scope.
  - **args** (Optional): Attributes to pass as the **second argument** to `callPackage`.
    - These are merged with inherited args from parent directories.
    - Useful for injecting dependencies or configuration into `package.nix`.
- **Granularity**: Works at both directory level (for groups of packages) and package level (sibling of `package.nix`).
- **Usage**: Essential for Python, Perl, and other language-specific package sets, or for injecting parameters into packages.


### Key Components

- **lib/**: Core utility library with Haskell-inspired functional programming patterns
  - `lib/flake-fhs.nix`: Entry point wrapper for `mkFlake`
  - `lib/fhs-core.nix`: Core implementation (`mkFlakeCore`)
  - `lib/fhs-modules.nix`: Module system logic and output generation
  - `lib/fhs-pkgs.nix`: Package loading logic
  - `lib/fhs-lib.nix`: Library preparation and recursive loader
  - `lib/fhs-config.nix`: Configuration options
  - `lib/pkg-tools.nix`: Package helper utilities
  - `lib/dict.nix`, `lib/list.nix`, `lib/file.nix`: Fundamental utilities

 - **templates/**: Project templates for different use cases
   - `default` *(recommended)*: Minimal template — only flake.nix, no pre-created directories
   - `embed` *(recommended)*: Embedded template with `./nix` directory (for non-Nix projects)
   - `short` *(reference)*: Template with short directory names (`modules`, `hosts`, `pkgs`, `apps`, `shells`)
   - `long` *(reference)*: Template with long directory names (`nixosModules`, `nixosConfigurations`) + colmena

## Module System Architecture

The framework implements a module system with **three mutually exclusive module types**:

### Module Types

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
   ├─ Identifier: Standalone file matching suffix (default: .nix)
   ├─ Features: Direct export, no enable mechanism
   └─ Use Case: Simple modules
```

### Module Loading Rules
1. **Guarded Modules**: Directories with `options.nix`
   - Auto-generates `enable` option if not manually defined
   - Config files (matching suffix, default `.nix`) are **recursively collected** from:
     - Current directory
     - All non-guarded subdirectories (regardless of `default.nix` presence)
   - All collected config files are wrapped with `mkIf enable`
   - Nested guarded modules check ALL parent enables (not just immediate parent)
   - **Conflict**: Cannot have both `options.nix` and `default.nix` in the same directory

2. **Traditional Modules**: Directories with `default.nix` (no `options.nix`)
   - Directly exported, no enable mechanism
   - **No nesting**: Subdirectories with `default.nix` are NOT recognized as modules

3. **Single File Modules**: Standalone files matching the configured suffix (default: `.nix`)
   - Directly exported, no enable mechanism
   - Found recursively in all non-guarded, non-traditional directories

### Module File Suffix Configuration
The file suffix for auto-discovering config files and single-file modules is configurable:
```nix
# flake.nix
flake-fhs.lib.mkFlake { inherit inputs; } {
  layout.nixosModules = {
    subdirs = [ "modules" ];
    suffix = ".mod.nix";  # Custom suffix (default: ".nix")
  };
}
```
This allows keeping helper `.nix` files that shouldn't be auto-imported alongside config files.

### Module Output Structure
- **Individual Module Outputs**: Each module generates a single output:
  - `nixosModules.<modPath>`: The complete module (options + config)
  - Example: `modules/services/web-server/` → `nixosModules.services.web-server`

- **Default Module Export**: `nixosModules.default` includes ALL modules:
  - All guarded modules (with their enable guards)
  - All traditional modules
  - All single file modules
  - Allows importing all modules with: `imports = [ flake.nixosModules.default ];`

### Nested Guarded Modules
When guarded modules are nested, child modules' configs check ALL parent enables:
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

### Strict Options Validation

By default, option namespace is not enforced. Enable `layout.nixosModules.strictOptions` to validate that each option's namespace matches its directory path:
- `modules/foo/options.nix` should define options under `options.foo.*`
- `modules/foo/bar/options.nix` should define options under `options.foo.bar.*`

When enabled, violations are reported via `config.assertions` at system evaluation time.

## Code Quality Standards

### Functional Programming Style
- Use immutable data structures
- Prefer function composition (use tool functions from `lib/` (i.e. `self.lib`) and `builtins` and `lib`)
- Implement higher-order functions for reusable operations and save general ones into `lib/`
- Follow the utility patterns established in `lib/dict.nix` and `lib/list.nix`
- Always add Haskell-style type-signatures for reusable or complex functions

### Nix Conventions
- Follow nixpkgs best practices for package definitions
- Use standard `pkgs/by-name/` structure for packages (`pkgs/<name>/package.nix`)
- Implement proper options and config separation in modules
- Leverage Nix's type system extensively

## Testing Infrastructure

### Template Validation System
- **Core (Nix)**: `checks/template-validation/default.nix` implements a pure-Nix validator that mocks inputs to evaluate all templates against the current library code. It runs automatically via `nix flake check`.
- **Feature Tests**: Standalone checks (e.g., `checks/flake-option.nix`, `checks/scope.nix`) validate specific library features by generating minimal flake structures in the Nix store.
- **Integration (Python)**: `checks/template-validation/validators.py` simulates real-world usage by creating temporary directories, replacing URLs, and running actual Nix commands. Use this for deep integration testing.

### Running Tests
```bash
nix flake check                                  # Standard test (CI friendly)
python checks/template-validation/validators.py  # Manual integration test (Full simulation)
```

### Nix Lazy Evaluation and Test Framework

**Critical Understanding**: Nix uses lazy evaluation, which has profound implications for test design.

#### The Problem
Unreferenced let bindings are never evaluated:
```nix
let
  checks = {
    test1 = if someCondition then throw "FAIL" else true;
  };
  # ❌ WRONG: checks is never used, so test1 is never evaluated!
in
pkgs.runCommand "test" { } ''
  echo "PASS"  # Hardcoded success message
  touch $out
''
```

#### The Solution
Tests must reference check results in the derivation to force evaluation:
```nix
let
  checks = {
    test1 = if someCondition then "FAIL: reason" else "PASS";
    test2 = builtins.length someList == 2 || "FAIL: expected 2 items";
  };
  checkResults = builtins.attrValues checks;
in
pkgs.runCommand "test" { } ''
  # Output actual check results (forces evaluation)
  ${builtins.concatStringsSep "\n" (map (r: "echo '${r}'") checkResults)}

  # Fail if any check failed
  if echo '${builtins.toJSON checks}' | grep -q FAIL; then
    exit 1
  fi

  touch $out
''
```

#### Key Principles
1. **Never hardcode test output** - Tests should output actual check results
2. **Force evaluation via derivation** - Reference check results in `runCommand` to ensure they're evaluated

## Project Configuration

### lib.mkFlake Usage
Typical flake.nix for users (showing common options):
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs = inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      # Optional: Explicitly specify systems (flake-parts style)
      systems = [ "x86_64-linux" "x86_64-darwin" ];

      # Optional: Nixpkgs configuration
      nixpkgs.config = {
        allowUnfree = true;
      };

      # Optional: Source roots
      # layout.roots = [ "" "/nix" ];

      # Optional: Enable Colmena integration
      # colmena.enable = true;
    };
}
```

## Colmena Integration

The framework provides native support for [Colmena](https://github.com/zhaofengli/colmena), a deployment tool for NixOS.

### Usage
To enable Colmena support, set `colmena.enable = true` in your `mkFlake` configuration. This will generate a `colmenaHive` output that can be used directly by Colmena.

```nix
outputs = inputs@{ flake-fhs, ... }:
  flake-fhs.lib.mkFlake { inherit inputs; } {
    # ...
    colmena.enable = true;
  };
```

### Features
- Automatically discovers nodes from `nixosConfigurations` directory structure.
- Injects `profileName` into module arguments for each node (accessible via `config.profileName`).
- Sets `deployment.allowLocalDeployment = true` by default.
- Inherits `nixpkgs` revision info from the flake inputs.

### mkFlake Architecture
The `mkFlake` function has been redesigned to use Nix's module system (`lib.evalModules`):
- **First parameter**: Context including `inputs`, `self`, `nixpkgs`, `lib`
- **Second parameter**: Configuration module with type-safe options
- **Core implementation**: `mkFlakeCore` (in `lib/fhs-core.nix`) contains the actual flake generation logic
- **Configuration options**: Defined in `flakeFhsOptions` (in `lib/fhs-config.nix`) with full type checking

## Development Guidelines

### AGENTS.md Maintenance Principles
- **Pattern over Enumeration**: Describe structures using patterns (e.g., `manual-*.md`) instead of exhaustive lists to reduce maintenance burden and noise.
- **Mechanism Focus**: Explain *shared mechanisms* (e.g., "Scoped Package Tree") to guide logical consistency across related components.
- **Conciseness**: Keep instructions high-level and directive. Avoid redundancy with the actual documentation content.

### Core Principles
- **SSOT & DRY**: Central `mkFlake` function handles all output generation
- **Convention Over Configuration**: Standardized directory structure eliminates boilerplate
- **Performance**: Partial loading mechanism for large module sets
- **Type Safety**: Leverages Nix's type system extensively

### File Organization
- Core logic split across `lib/fhs-*.nix` files (`core`, `modules`, `pkgs`, `config`, `lib`)
- Entry point in `lib/flake-fhs.nix`
- Shared utilities in `lib/` directory
- Templates in `templates/` with embedded documentation
- Module system guide in `docs/manual-modules.md`
- User-facing documentation site: [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs)

### When Modifying Code
1. **Utility Functions**: Reuse existing utilities from `lib/` directory
2. **Module System**: Maintain guarded/unguarded module loading behavior
3. **Template Updates**: Ensure templates work with current `mkFlake` implementation
4. **Testing**: Run template validation after changes that affect flake outputs
5. **Documentation**: Update `docs/manual-modules.md` for module system changes. Update user-facing docs in the [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) repo.

## Documentation Structure

- **In-repo**: `docs/manual-modules.md` — module system developer guide
- **User-facing**: [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) — Starlight site with bilingual (en/zh-cn) docs
