# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Flake FHS** (Flake Flake Hierarchy Standard) is a framework for Nix flakes that automatically generates flake outputs from a standardized directory structure, eliminating the need to write repetitive `flake.nix` boilerplate code.

## Core Architecture

### Directory Mapping System

The framework implements an automatic mapping from directory structure to flake outputs:

| Subdirectories (Aliases) | File Pattern | Special Files | Recursive | Generated Output | Nix Command |
|---|---|---|:---:|---|---|
| `packages` (`pkgs`) | `<name>/package.nix` | `default.nix`, `scope.nix` | ✅ | `packages.<system>.<name>` | `nix build .#<name>` |
| `nixosModules` (`modules`) | `<name>/...` | `options.nix`, `default.nix` | ✅ | `nixosModules.<name>` | - |
| `nixosConfigurations` (`hosts`, `profiles`) | `<name>/configuration.nix` | - | ✅ | `nixosConfigurations.<name>` | `nixos-rebuild --flake .#<name>` |
| `apps` | `<name>/package.nix` | `default.nix` | ✅ | `apps.<system>.<name>` | `nix run .#<name>` |
| `devShells` (`shells`) | `<name>.nix` | `default.nix` | ✅ | `devShells.<system>.<name>` | `nix develop .#<name>` |
| `templates` | `<name>/` | `flake.nix` | ❌ | `templates.<name>` | `nix flake init --template <url>#<name>` |
| `lib` (`utils`, `tools`) | `<name>.nix` | - | ✅ | `lib.<name>` | `nix eval .#lib.<name>` |
| `checks` | `<name>.nix` | `default.nix` | ✅ | `checks.<system>.<name>` | `nix flake check .#<name>` |

### Package Scope System

The framework supports custom dependency scopes for packages via `scope.nix`:
- **File**: `<dir>/scope.nix`
- **Function**: `pkgs: newScope`
- **Behavior**: The returned scope applies to `package.nix` in the current directory and recursively to subdirectories.
- **Usage**: Essential for Python, Perl, and other language-specific package sets.

### Key Components

- **lib/**: Core utility library with Haskell-inspired functional programming patterns
  - `lib/prepare-lib.nix`: Library loading and layering system
  - `lib/dict.nix`: Dictionary operations and higher-order functions
  - `lib/list.nix`: List operations
  - `lib/file.nix`: File system operations
  - `lib/flake-fhs.nix`: Core `mkFlake` implementation
  - `lib/more/`: Extended utilities requiring `pkgs`
    - `lib/more/package.nix`: Package helpers (e.g. `inferMainProgram`)

 - **templates/**: Project templates for different use cases
   - `std`: Standard template with complete nixos-config and flake outputs 1:1 naming
   - `short`: Short-named template with complete nixos-config
   - `zero`: Minimal template with only flake.nix (directories left for user to create)
   - `project`: Project-embedded template with `./nix` directory (for non-Nix projects)

## Module System Architecture

The framework implements an advanced module loading system:

- **Guarded vs Unguarded Modules**: Directories containing `options.nix` are "guarded" (default disabled), others are "unguarded" (default enabled)
- **Partial Loading**: Implements performance optimization by loading only necessary modules
- **Auto-enable Options**: Automatically generates enable options for guarded modules (if not manually defined)
- **Module Discovery**: Automatically discovers and imports modules based on directory structure
- **Option Nesting**: Automatically nests options under module paths (default behavior, configurable via `optionsMode`) (e.g. `services/web-server/options.nix` -> `options.services.web-server.*`) and auto-generates `enable` option (if missing)

### Module Loading Rules
1. All unguarded directory modules are imported
   - If a directory contains `default.nix`, it is treated as a leaf module (recursion stops) and only `default.nix` is imported
   - Otherwise, all `.nix` files in the directory are imported and subdirectories are recursed
2. All guarded directory `options.nix` files are imported
3. Only enabled guarded modules (enable = true) import their config files

### Options Processing Modes
The `options.nix` processing behavior can be configured via `optionsMode`:
- **strict** (default): No automatic nesting. Enforces that defined options strictly match the directory structure.
- **auto**: Automatically nests options under the directory path (e.g. `foo/options.nix` -> `options.foo.*`) and auto-generates `enable` option.
- **free**: No automatic nesting. Allows arbitrary option definitions.

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
    };
}
```

### mkFlake Architecture
The `mkFlake` function has been redesigned to use Nix's module system (`lib.evalModules`):
- **First parameter**: Context including `inputs`, `self`, `nixpkgs`, `lib`
- **Second parameter**: Configuration module with type-safe options
- **Core implementation**: `mkFlakeCore` contains the actual flake generation logic
- **Configuration options**: Defined in `flakeFhsOptions` submodule with full type checking

## Development Guidelines

### Core Principles
- **SSOT & DRY**: Central `mkFlake` function handles all output generation
- **Convention Over Configuration**: Standardized directory structure eliminates boilerplate
- **Performance**: Partial loading mechanism for large module sets
- **Type Safety**: Leverages Nix's type system extensively

### File Organization
- Core logic in `lib/flake-fhs.nix`
- Shared utilities in `lib/` directory
- Templates in `templates/` with embedded documentation
- Comprehensive manual in `docs/manual.md`

### When Modifying Code
1. **Utility Functions**: Reuse existing utilities from `lib/` directory
2. **Module System**: Maintain guarded/unguarded module loading behavior
3. **Template Updates**: Ensure templates work with current `mkFlake` implementation
4. **Testing**: Run template validation after changes that affect flake outputs

## Documentation

- **User Manual**: `docs/manual.md` (comprehensive usage guide in Chinese)
- **Template READMEs**: Individual template documentation
- **Inline Comments**: Extensive comments in Nix files explaining design decisions
- **Code Examples**: Each template includes working examples

The project is well-documented for Chinese-speaking users and includes detailed explanations of design patterns and usage examples.
