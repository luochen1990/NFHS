Flake FHS
=========
**Flake Filesystem Hierarchy Standard**

Flake FHS 是一个面向 Nix flake 的文件系统层级规范，它同时提供一个默认的 `flake.nix` 实现（`mkFlake`）。
用户几乎不需要自己编写 `flake.nix`。只需将 Nix 代码放置在约定的目录结构中，Flake FHS 就会自动映射并生成所有对应的 flake outputs。

它是一个 **“约定优于配置”** 的 flake 项目布局标准。

Flake FHS 致力于解决以下核心问题：

- 项目之间 flake 结构差异过大，难以理解与复用
- 为每个项目重复编写大量 `flake.nix` boilerplate
- 工具无法推断目录语义，导致自动化困难

Flake FHS 提供：

1. 一个 **固定、可预测、可扩展** 的 flake 项目目录规范
2. 一个 **自动生成 flake outputs** 的默认实现

---

## 🚀 快速开始

使用 Flake FHS 时典型项目**目录结构**如下：

```
.
├── pkgs/       # flake-output.packages
├── modules/    # flake-output.nixosModules
├── profiles/   # flake-output.nixosConfigurations
├── shells/     # flake-output.devShells
├── apps/       # flake-output.apps
├── lib/        # flake-output.lib
├── checks/     # flake-output.checks
└── templates/  # flake-output.templates
```

根目录仅需简短的 flake.nix 文件，**无需手写 flake outputs**：

```nix
{
  inputs.fhs.url = "github:luochen1990/flake-fhs";

  outputs = { fhs, ... }:
    fhs.mkFlake { root = [ ./. ]; };
}
```

Flake FHS 会自动扫描目录、构建对应输出、并生成结构完整的 flake outputs

## 📁 核心映射关系

Flake FHS 建立了文件系统到 flake outputs 的直接映射关系：

**文件路径 → flake output → Nix 子命令**

| 文件路径  | 生成的 flake output  |  Nix 子命令         |
| ------------- | ------------------ | ------------------------ |
| `pkgs/<name>/package.nix`      | `packages.<system>.<name>`                   | `nix build .#<name>`               |
| `modules/<name>/path/to/filename.nix`   | `nixosModules.<name>`  | nope |
| `profiles/<name>/configuration.nix`   | `nixosConfigurations.<name>`  | `nixos-rebuild --flake .#<name>`    |
| `apps/<name>/default.nix`      | `apps.<system>.<name>`                       | `nix run .#<name>`                 |
| `shells/<name>.nix` | `devShells.<system>.<name>`                  | `nix develop .#<name>`             |
| `templates/<name>/`    | `templates.<name>`                           | `nix flake init --template <url>#<name>` |
| `lib/<name>.nix`       | `lib.<name>`                                 | `nix eval .#lib.<name>`            |
| `checks/<name>.nix`       | `checks.<system>.<name>`                                 | `nix flake check .#<name>`            |

---

## ✨ 核心特性

- **自动发现**：所有 `<name>` 来自文件/目录名，无需手动声明
- **跨平台支持**：`<system>` 根据配置自动生成，默认使用当前系统平台
- **零配置映射**：所有映射关系由 Flake FHS 自动完成
- **约定优于配置**：遵循 Nixpkgs 的最佳实践和目录结构

---

## 🛠️ 本项目结构

本项目是 Flake FHS 的核心实现，只包含框架代码：

- `utils/` - 核心工具函数库（从 `~/ws/nixos/tools/` 搬运）
- `flake.nix` - 包含 `mkFlake` 函数的主要实现
- `templates/` - 项目模板集合
- `docs/` - 详细文档和手册

## 📋 项目模板

Flake FHS 提供了三种模板来快速启动不同类型的项目：

### 🚀 simple-project
适合简单的包开发和工具项目，包含：
- 包定义示例 (`pkgs/hello/`)
- 多种开发环境 (`shells/`)
- 应用程序示例 (`apps/greeting/`)
- 工具函数库 (`lib/utils/`)

### 🏗️ package-module
适合 NixOS 模块开发，展示模块化设计：
- 模块选项定义 (`modules/my-service/options.nix`)
- 模块配置实现 (`modules/my-service/config.nix`)
- 系统配置示例 (`profiles/example/`)

### 🔧 full-featured
包含所有功能的完整项目模板：
- 完整的目录结构
- 跨平台支持配置
- 最佳实践示例

### 使用模板

```bash
# 创建简单项目
nix flake init --template github:luochen1990/flake-fhs#simple-project

# 创建 NixOS 模块项目
nix flake init --template github:luochen1990/flake-fhs#package-module

# 创建完整功能项目
nix flake init --template github:luochen1990/flake-fhs#full-featured
```

### 示例用法

以 `simple-project` 模板为例：

```bash
# 查看所有可用的包
nix flake show --json | jq '.packages."x86_64-linux"'

# 构建示例包
nix build .#hello-custom

# 进入开发环境
nix develop

# 运行应用
nix run .#greeting

# 查看工具函数
nix eval .#lib.utils.strings.camelCase --apply 'f: f "hello-world"'
```

---

## 📦 mkFlake 配置选项

```nix
fhs.mkFlake {
  # 必需：根目录列表
  root = [ ./. ];

  # 可选：支持的系统架构
  supportedSystems = [ "x86_64-linux" "x86_64-darwin" ];

  # 可选：nixpkgs 配置
  nixpkgsConfig = {
    allowUnfree = true;
    # 其他 nixpkgs 配置...
  };
}
```

详细用法见: [使用手册](./docs/manual.md)

## 许可证

MIT License

<!--
Copyright © 2025 罗宸 (luochen1990@gmail.com)
-->
