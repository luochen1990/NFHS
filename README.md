# Flake FHS

**Flake FHS** (Flake Filesystem Hierarchy Standard) 是一个 Nix Flake 框架。它通过标准化的目录结构自动生成 flake outputs，旨在解决 Nix 项目配置中的常见痛点。

## 项目动机

在维护多个 Nix Flake 项目时，我们经常面临以下问题：

1.  **样板代码重复**：每个项目都需要编写大量雷同的 `flake.nix` 代码来处理 inputs、systems 遍历和模块导入。
2.  **结构差异巨大**：缺乏统一的目录规范，导致接手不同项目时需要花费额外精力理解其文件组织方式。
3.  **工具链集成难**：由于缺乏标准化的目录语义，难以开发通用的自动化工具来辅助开发。

Flake FHS 通过引入一套**固定且可预测**的目录规范来解决这些问题。你只需将文件放入约定的目录，框架会自动处理剩余的工作。

## 目录映射概览

Flake FHS 将文件系统的目录结构直接映射为 Flake Outputs：

| 目录 | 对应 Flake Output | 说明 |
|---|---|---|
| `pkgs/` | `packages` | 包含 `package.nix` 的子目录会被识别为包 |
| `modules/` | `nixosModules` | 自动发现并组合 NixOS 模块 |
| `hosts/` | `nixosConfigurations` | 每个子目录对应一个 NixOS 系统配置 |
| `apps/` | `apps` | 定义可运行的应用程序 (目录结构同 `pkgs/`) |
| `shells/` | `devShells` | 开发环境定义 |
| `lib/` | `lib` | 扩展 `lib` 函数库 |
| `checks/` | `checks` | CI/CD 检查项 |
| `templates/` | `templates` | 项目初始化模板 |

## 快速开始

1.  **初始化项目**

    Flake FHS 提供了针对不同场景的模板：

    ```bash
    # 标准模板 (Standard)
    # 包含完整功能，使用标准目录命名 (packages, nixosModules, ...)
    nix flake init --template github:luochen1990/flake-fhs#std

    # 简短模板 (Short)
    # 包含完整功能，使用简短目录命名 (pkgs, modules, ...)
    nix flake init --template github:luochen1990/flake-fhs#short

    # 最小模板 (Zero)
    # 仅包含 flake.nix，适合从零开始构建
    nix flake init --template github:luochen1990/flake-fhs#zero

    # 项目内嵌模板 (Project)
    # 适用于非 Nix 主导的项目 (如 Python/Node.js 项目)，将 Nix 配置隔离在 ./nix 目录下
    nix flake init --template github:luochen1990/flake-fhs#project
    ```

2.  **配置 `flake.nix`**

    最简配置仅需一行：

    ```nix
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        flake-fhs.url = "github:luochen1990/flake-fhs";
      };

      outputs = inputs: inputs.flake-fhs.lib.mkFlake { inherit inputs; } { };
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
      networking.hostName = "my-machine";
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
