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
| `nixosModules` (`modules`) | `<name>/default.nix` or `<name>.nix` | `*.cfg.nix` | ✅ | `nixosModules.<name>` | - |
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

### self': Project-Internal Outputs View

`self'` ("self prime", named after the flake-parts convention) is a **system-resolved, raw-scan view of the project's own outputs**. It reads as "self with the system already selected" — `self'.packages.foo` ≡ `self.packages.${system}.foo` in spirit, but see the semantic difference below.

**Visibility (where `self'` is reachable):**

- **`shells/*.nix` and `shells/*/default.nix`** — automatically available, since these files are called as `import file evalContext` and `evalContext.self'` is in scope:
  ```nix
  # shells/dev.nix
  { pkgs, self', ... }:
  pkgs.mkShell {
    packages = [ self'.packages.my-cli ];
    inputsFrom = [ self'.apps.my-tool ];  # or builtins.attrValues self'.packages
  }
  ```
- **`pkgs/*/package.nix`, `apps/*/package.nix`, `checks/*.nix`** — **NOT reachable**. These are called via `callPackage` (whose scope is `pkgs`-derived and does not include `self'`), and a sibling `scope.nix` cannot inject `self'` either (see the "Caveat" below). To share logic between packages, factor it into `lib/`.

**Design contract (why this is safe from infinite recursion):**

- `self'.packages` / `self'.apps` / `self'.checks` are **raw scan results** from `loadScopedOutputs` — the same intermediate values used to assemble the final `flake.packages` / `flake.apps` / `flake.checks`. Each entry is the **raw derivation** (for `apps`, this is the underlying drv, not the `{ type="app"; program=...; }` wrapper — so use `inputsFrom`, not `.program`).
- The dependency graph is a **DAG, not a cycle**: `loadScopedOutputs → self' → devShells` and `loadScopedOutputs → final flake outputs` are two independent consumers of the same scan.
- This is structurally stronger than flake-parts' `self'` (which points to the *final* flake outputs and relies on lazy evaluation to avoid the self-reference loop). flake-fhs's construction model makes the loop **structurally impossible**.

**Caveat — `scope.nix` cannot consume `self'`:**

`self'` itself is built from a `baseCtx` (evalContext *without* `self'`) to break the self-reference. Therefore a `scope.nix` that reads `context.self'` will hit `attribute 'self'' missing` during `self'`'s own construction. **Only consume `self'` from `shells/*.nix`** (which receive the full `evalContext` after `self'` is bound); never reference `self'` inside `scope.nix` or `package.nix`.

**What's intentionally NOT exposed on `self'`:**

- **`devShells`** — exposing it would re-introduce the cycle hazard (devShells are user-defined functions, not scanned outputs). To share logic between shells, factor common code into `lib/`.
- **`nixosConfigurations` / `nixosModules` / `templates`** — these are not derivation-valued, and the primary use case for `self'` is feeding `mkShell.inputsFrom` / `packages`.


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

> **Documentation**: All user-facing documentation lives in the [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) repo as the single source of truth (SSOT). This repo contains only code, tests, and this developer guide.

## Module System Architecture

The framework implements a **unified module system** based on `default.nix` as the single entry point. There are no "module types" — only **guarded config files** (`.cfg.nix`) as a file-level attribute.

### Core Concepts

```
Module entry points (unified, no type distinction)
│
├─ Directory Module
│  ├─ Identifier: Directory contains default.nix
│  ├─ Entry: default.nix (options + base config)
│  ├─ Enable injection: ALWAYS injects <modPath>.enable (if not manually defined)
│  │  This guarantees the enable-chain is self-consistent.
│  └─ Nesting: supported; child modules' enable-chain includes all ancestor modules' enables
│
└─ Single File Module
   ├─ Identifier: Standalone `.nix` file, not inside any directory module's subtree
   ├─ No enable injection, no enable-chain
   └─ Use Case: Simple modules

Guarded config file (file-level attribute, not a module type)
│
└─ .cfg.nix (configurable via layout.nixosModules.guardedSuffix)
   ├─ Must reside within a directory module's subtree
   ├─ Content is wrapped with mkIf (enable-chain)
   └─ Auto-imported by the enclosing directory module
```

### enable-chain (precise definition)

A `.cfg.nix`'s mkIf condition = the AND of **all ancestor module enables** (directories with `default.nix` on the path) AND **the enclosing module's own enable**.

Intermediate directories without `default.nix` (pure path organization) do NOT participate in the enable-chain, but still contribute modPath segments.

Example:
```
modules/
└── network/              # has default.nix → module, in chain
    ├── default.nix       # injects network.enable
    ├── net.cfg.nix       # mkIf config.network.enable
    └── services/         # no default.nix → path segment, NOT in chain
        └── web/           # has default.nix → module, in chain
            ├── default.nix  # injects network.services.web.enable
            └── web.cfg.nix  # mkIf (config.network.enable && config.network.services.web.enable)
```

### Module Loading Rules

1. **Directory Modules**: Directories with `default.nix`
   - `default.nix` config is **always applied** (no mkIf wrapping)
   - `<modPath>.enable` is auto-injected (if not manually defined) — this is required for enable-chain consistency
   - `.cfg.nix` files within the module's scope are collected (recursively, stopping at sub-module boundaries) and wrapped with `mkIf (enable-chain)`
   - Nested directory modules' `.cfg.nix` checks ALL ancestor module enables

2. **Single File Modules**: Standalone `.nix` files that are **not inside any directory module's subtree**
   - Directly exported, no enable injection
   - Files inside a directory module's subtree (except `.cfg.nix`) are managed by the module's `default.nix` and are NOT auto-discovered

### Module File Suffix Configuration
The guarded config suffix is configurable:
```nix
# flake.nix
flake-fhs.lib.mkFlake { inherit inputs; } {
  layout.nixosModules = {
    subdirs = [ "modules" ];
    guardedSuffix = ".guarded.nix";  # Custom suffix for guarded config files (default: ".cfg.nix")
  };
}
```

### Module Output Structure
- **Individual Module Outputs**: Each module generates a single output:
  - `nixosModules.<modPath>`: The complete module (default.nix + collected .cfg.nix)
  - Example: `modules/services/web-server/` → `nixosModules.services/web-server`

- **Default Module Export**: `nixosModules.default` includes ALL modules:
  - All directory modules (with their enable injection and .cfg.nix guards)
  - All single file modules
  - Allows importing all modules with: `imports = [ flake.nixosModules.default ];`

### Strict Options Validation

By default, option namespace is not enforced. Enable `layout.nixosModules.strictOptions` to validate that each option's namespace matches its directory path:
- `modules/foo/default.nix` should define options under `options.foo.*`
- `modules/foo/bar/default.nix` should define options under `options.foo.bar.*`

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
      systems = [ "x86_64-linux" "aarch64-darwin" ];

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
- **Core logic**: split across `lib/fhs-*.nix` files (`core`, `modules`, `pkgs`, `config`, `lib`)
- **Entry point**: `lib/flake-fhs.nix`
- **Shared utilities**: `lib/` directory
- **Templates**: `templates/` with embedded documentation
- **Documentation**: [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) — Starlight site with bilingual (en/zh-cn) docs (SSOT)

### When Modifying Code
1. **Utility Functions**: Reuse existing utilities from `lib/` directory
2. **Module System**: Maintain guarded/unguarded module loading behavior
3. **Template Updates**: Ensure templates work with current `mkFlake` implementation
4. **Testing**: Run template validation after changes that affect flake outputs
5. **Documentation**: Update user-facing docs in the [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) repo.

## Documentation Structure

- **SSOT**: [flake-fhs-docs](https://github.com/luochen1990/flake-fhs-docs) — Starlight site with bilingual (en/zh-cn) docs
- **In-repo**: `AGENTS.md` (this file) — developer guide for code contributors only
