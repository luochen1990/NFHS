# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nix FHS** (Nix Flake Hierarchy Standard) is a framework for Nix flakes that automatically generates flake outputs from a standardized directory structure, eliminating the need to write repetitive `flake.nix` boilerplate code.

## Core Architecture

### Directory Mapping System

The framework implements an automatic mapping from directory structure to flake outputs:

| Directory | Generated Output | Nix Command |
|-----------|------------------|-------------|
| `pkgs/<name>/package.nix` | `packages.<system>.<name>` | `nix build .#<name>` |
| `modules/<name>/...` | `nixosModules.<name>` | - |
| `profiles/<name>/configuration.nix` | `nixosConfigurations.<name>` | `nixos-rebuild --flake .#<name>` |
| `apps/<name>/default.nix` | `apps.<system>.<name>` | `nix run .#<name>` |
| `shells/<name>.nix` | `devShells.<system>.<name>` | `nix develop .#<name>` |
| `templates/<name>/` | `templates.<name>` | `nix flake init --template <url>#<name>` |
| `utils/<name>.nix` | `lib.<name>` | `nix eval .#lib.<name>` |
| `checks/<name>.nix` | `checks.<system>.<name>` | `nix flake check .#<name>` |

### Key Components

- **utils/**: Core utility library with Haskell-inspired functional programming patterns
  - `utils/utils.nix`: Chainable utils preparation system
  - `utils/dict.nix`: Dictionary operations and higher-order functions
  - `utils/list.nix`: List operations
  - `utils/file.nix`: File system operations
  - `utils/more/fhs.nix`: Core `mkFlake` implementation

 - **templates/**: Project templates for different use cases
   - `std`: Standard template with complete nixos-config and flake outputs 1:1 naming
   - `short`: Short-named template with complete nixos-config
   - `zero`: Minimal template with only flake.nix (directories left for user to create)
   - `project`: Project-embedded template with `./nix` directory (for non-Nix projects)

## Module System Architecture

The framework implements an advanced module loading system:

- **Guarded vs Unguarded Modules**: Directories containing `options.nix` are "guarded" (default disabled), others are "unguarded" (default enabled)
- **Partial Loading**: Implements performance optimization by loading only necessary modules
- **Auto-enable Options**: Automatically generates enable options for guarded modules
- **Module Discovery**: Automatically discovers and imports modules based on directory structure

### Module Loading Rules
1. All unguarded directory modules are imported
2. All guarded directory `options.nix` files are imported
3. Only enabled guarded modules (enable = true) import their config files

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
- **Integration (Python)**: `checks/template-validation/validators.py` simulates real-world usage by creating temporary directories, replacing URLs, and running actual Nix commands. Use this for deep integration testing.

### Running Tests
```bash
nix flake check                                  # Standard test (CI friendly)
python checks/template-validation/validators.py  # Manual integration test (Full simulation)
```

## Project Configuration

### lib.mkFlake Usage
Typical flake.nix for users:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-fhs.url = "github:luochen1990/Nix-FHS";
  };

  outputs = { self, nixpkgs, nix-fhs, ... }:
    nix-fhs.lib.mkFlake {
      inherit self nixpkgs;
    };
}
```

### Advanced Configuration
```nix
nix-fhs.lib.mkFlake {
  inherit self nixpkgs;
  roots = [ ./. ./nix ];
  supportedSystems = [ "x86_64-linux" "x86_64-darwin" ];
  nixpkgsConfig = {
    allowUnfree = true;
  };
}
```

## Development Guidelines

### Core Principles
- **SSOT & DRY**: Central `mkFlake` function handles all output generation
- **Convention Over Configuration**: Standardized directory structure eliminates boilerplate
- **Performance**: Partial loading mechanism for large module sets
- **Type Safety**: Leverages Nix's type system extensively

### File Organization
- Core logic in `lib/nfhs.nix`
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
