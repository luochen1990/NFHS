Nix Flake Hierarchy Standard (NixFHS)
===

NixFHS 是一个面向 Nix flake 的目录规范，它同时提供一个默认的 `flake.nix` 实现（`mkFlake`）。
用户几乎不需要自己编写 `flake.nix`。只需将 Nix 代码放置在约定的目录结构中，NixFHS 就会自动映射并生成所有对应的 flake outputs。

它约定了 flake 项目的目录布局。

NixFHS 致力于解决以下核心问题：

- 项目之间 flake 结构差异过大，难以理解与复用
- 为每个项目重复编写大量 `flake.nix` boilerplate
- 工具无法推断目录语义，导致自动化困难

NixFHS 提供：

1. 一个 **固定、可预测、可扩展** 的 flake 项目目录规范
2. 一个 **自动生成 flake outputs** 的默认实现

---

## 🚀 快速开始

使用 NixFHS 时典型项目**目录结构**如下：

```
.
├── pkgs/       # flake-output.packages
├── modules/    # flake-output.nixosModules
├── profiles/   # flake-output.nixosConfigurations
├── shells/     # flake-output.devShells
├── apps/       # flake-output.apps
├── lib/        # flake-output.lib (for tool functions)
├── checks/     # flake-output.checks
└── templates/  # flake-output.templates
```

NixFHS 提供了若干模板来快速启动不同类型的项目：

```bash
# 标准模板（完整功能，标准命名）
nix flake init --template github:luochen1990/Nix-FHS#std

# 简短模板（完整功能，简短命名）
nix flake init --template github:luochen1990/Nix-FHS#short

# 最小模板（仅 flake.nix）
nix flake init --template github:luochen1990/Nix-FHS#zero

# 项目内嵌模板（非纯 Nix 项目）
nix flake init --template github:luochen1990/Nix-FHS#project
```

这将直接为你生成一个简洁并且合法的 flake.nix 文件：

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

之后你只需要在对应的目录里添加配置即可，**无需手写 flake outputs**

详细用法见: [使用手册](./docs/manual.md)

## 许可证

MIT License

<!--
Copyright © 2025 罗宸 (luochen1990@gmail.com)
-->
