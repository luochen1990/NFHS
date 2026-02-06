# Flake FHS

**Flake FHS** (Flake Filesystem Hierarchy Standard) 是一个 Nix Flake 框架。它通过标准化的目录结构自动生成 flake outputs，旨在解决 Nix 项目配置中的常见痛点。

## 项目动机

在维护多个 Nix Flake 项目时，我们经常面临以下问题：

1.  **样板代码重复**：每个项目都需要编写大量雷同的 `flake.nix` 代码来处理 inputs、systems 遍历和模块导入。
2.  **结构差异巨大**：缺乏统一的目录规范，导致接手不同项目时需要花费额外精力理解其文件组织方式。
3.  **工具链集成难**：由于缺乏标准化的目录语义，难以开发通用的自动化工具来辅助开发。

Flake FHS 通过引入一套**固定且可预测**的目录规范来解决这些问题。你只需将文件放入约定的目录，框架会自动处理剩余的工作。

## 目录映射规则表

Flake FHS 将文件系统的目录结构直接映射为 Flake Outputs：

| 目录 (及别名) | 对应 Flake Output | 说明 |
|---|---|---|
| `nixosConfigurations/` (`hosts`) | `nixosConfigurations` | 扫描子目录；每个含 `configuration.nix` 的目录对应一个主机配置 |
| `nixosModules/` (`modules`) | `nixosModules` | 递归扫描；含 `options.nix` 的目录自动生成 `enable` 选项 |
| `packages/` (`pkgs`) | `packages` | 递归扫描；识别 `<name>.nix` 或 `<name>/package.nix` |
| `apps/` | `apps` | 结构同 `packages`；自动推导可执行程序路径 |
| `checks/` | `checks` | 结构同 `packages`；定义 CI/CD 检查项 |
| `devShells/` (`shells`) | `devShells` | 识别 `<name>.nix`；定义开发环境 |
| `lib/` | `lib` | 递归扫描 `.nix` 文件；构建扩展函数库 |
| `templates/` | `templates` | 每个一级子目录为一个模板；非递归扫描 |

## 核心特性

*   **基于目录结构的自动发现 (Convention over Configuration)**
    Flake FHS 将文件系统的目录结构直接映射为 Flake Outputs，实现了高度的自动化：
    *   **统一的包管理 (Pkgs, Apps, Checks)**: 采用统一的 `package.nix` + `scope.nix` 模型。系统自动发现并通过 `callPackage` 构建包，支持灵活的依赖注入（如自动注入全局 inputs 或特定语言环境），无需手动维护包列表。
    *   **智能模块加载 (Modules)**: 自动递归发现 `modules/` 下的 NixOS 模块。对于包含 `options.nix` 的目录（Guarded Modules），系统会自动生成 `enable` 选项，实现了模块的“声明即注册，启用即加载”。

*   **统一的构建范式 (Unified Build Paradigm)**
    打破了不同 Flake Outputs 之间的定义壁垒。无论是软件包 (`pkgs`)、应用程序 (`apps`) 还是测试用例 (`checks`)，均采用统一的 `package.nix` + `callPackage` 机制构建，共享相同的依赖注入机制。这意味着你只需掌握一种定义方式，即可应用于项目的各个部分。

*   **优化的开发体验 (Developer Experience)**
    框架内置了对 `treefmt` 的支持，确保代码风格统一。同时，系统支持从 `packages` 自动派生 `devShells`，让你能一键进入任何包的调试环境，无需重复定义开发环境。

*   **渐进式采用**
    设计上支持混合模式。你可以仅让 Flake FHS 接管一部分输出（如只管理 `packages`），而将 `nixosConfigurations` 留给传统方式定义，从而实现平滑迁移现有项目。

*   **Colmena 集成**
    开箱即用的 [Colmena](https://github.com/zhaofengli/colmena) 支持。只需在全局配置中开启 `colmena.enable = true`，即可利用 Colmena 进行高效的多主机并行部署。

## 快速开始

1.  **初始化项目**

    Flake FHS 提供了针对不同场景的模板：

    标准模板 (Standard): 
    创建完整目录树，使用标准目录命名 (packages, nixosModules, nixosConfigurations, ...)

    ```bash
    nix flake init --template github:luochen1990/flake-fhs#std
    ```

    简短模板 (Short): 
    创建完整目录树，使用简短目录命名 (pkgs, modules, hosts, ...)

    ```bash
    nix flake init --template github:luochen1990/flake-fhs#short
    ```

    最小模板 (Zero): 
    不创建目录树, 仅包含 flake.nix，适合从零开始构建
    ```bash
    nix flake init --template github:luochen1990/flake-fhs#zero
    ```

    项目内嵌模板 (Project): 
    适用于非 Nix 主导的项目 (如 Python/Node.js 项目)，将 Nix 配置隔离在 ./nix 目录下
    ```bash
    nix flake init --template github:luochen1990/flake-fhs#project
    ```

2.  **配置 `flake.nix`**

    典型配置如下 (风格类似 flake-parts)：

    ```nix
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        flake-fhs.url = "github:luochen1990/flake-fhs";
      };

      outputs = inputs@{ flake-fhs, ... }:
        flake-fhs.lib.mkFlake { inherit inputs; } {
          # 可选: 指定支持的系统架构列表
          systems = [ "x86_64-linux" ];

          # 可选: 传递给 nixpkgs 实例的全局配置
          nixpkgs.config = {
            allowUnfree = true;
          };

          # 可选: 类似 flake-parts 的对应选项, 在 flake-fhs 中它主要用来添加非标准的 flake outputs
          flake = {
            ...
          }
        };
    }
    ```

    **渐进式迁移 (Progressive Migration)**

    如果你已有一个庞大的 flake，不必一次性重构所有内容。你可以仅使用 `flake-fhs` 管理部分输出 (如 `packages`)，其余部分暂时保持原样, 以实现逐步迁移。

    ```nix
    {
      # ... inputs ...

      outputs = inputs@{ self, nixpkgs, flake-fhs, ... }:
        let
          # 1. 创建 flake-fhs 实例，但不直接作为 outputs 返回
          fhs = flake-fhs.lib.mkFlake { inherit inputs; } { };
        in
        {
          # 2. 从 flake-fhs 中“摘取”你想迁移的部分 (例如 packages)
          packages = fhs.packages;

          # 3. 其他部分保持原有的手动定义方式
          nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
            # ... old config ...
          };
        };
    }
    ```

3.  **常用操作**

    **添加一个软件包**:
    创建 `pkgs/hello/package.nix`:
    ```nix
    { stdenv, fetchurl }:
    stdenv.mkDerivation {
      name = "hello-2.10";
      # ... standard derivation ...
    }
    ```
    构建：`nix build .#hello`

    **添加一个 NixOS 主机**:
    创建 `hosts/my-machine/configuration.nix`:
    ```nix
    { pkgs, ... }:
    {
      imports = [ ./hardware-configuration.nix ];
      system.stateVersion = "26.05";
    }
    ```
    部署：`nixos-rebuild switch --flake .#my-machine`

## 文档

详细的使用说明、配置选项及代码示例，请参阅 [用户手册 (Manual)](./docs/manual.md)。

## 许可证

MIT License

<!--
Copyright © 2025 罗宸 (luochen1990@gmail.com)
-->
