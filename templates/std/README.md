# Standard Template

标准模板，包含完整的 NixOS 系统配置功能，遵循 flake outputs 1:1 的标准命名约定。

## 项目结构

```
.
├── packages/                # flake-output.packages
│   ├── hello/              # 示例包：问候程序
│   └── fortune/            # 示例包：Fortune 生成器
├── nixosModules/            # flake-output.nixosModules
│   └── services/my-service/ # 示例 NixOS 模块
│       ├── options.nix     # 模块选项定义
│       ├── config.nix      # 模块配置实现
│       └── default.nix     # 模块入口
├── nixosConfigurations/     # flake-output.nixosConfigurations
│   └── example/            # 示例系统配置
│       └── configuration.nix
├── devShells/               # flake-output.devShells
│   ├── default.nix         # 默认开发环境
│   └── rust.nix           # Rust 开发环境
├── apps/                   # flake-output.apps
│   ├── status/            # 项目状态应用
│   └── deploy/            # 部署助手应用
├── checks/                 # flake-output.checks
│   ├── format.nix         # 代码格式检查
│   ├── lint.nix           # 代码质量检查
│   └── unit/              # 单元测试
│       └── default.nix
├── flake.nix              # 项目配置
└── README.md              # 本文档
```

## 功能特性

### 📦 **包管理**
- 自动发现 `packages/<name>/package.nix` 文件
- 标准的 Nixpkgs 包定义格式
- 示例：`hello` 和 `fortune` 包

### 🏗️ **模块系统**
- 带选项分离的 NixOS 模块
- 支持部分加载和条件启用
- 示例：`my-service` 模块，展示完整的选项定义和配置

### 💻 **系统配置**
- 完整的 NixOS 系统配置
- 自动模块导入
- 示例：包含自定义服务、网络配置、用户管理等

### 🔧 **开发环境**
- 多种开发环境支持
- 工具链集成和环境变量配置
- 示例：默认环境和 Rust 专用环境

### 🚀 **应用程序**
- 命令行应用封装
- 脚本和工具集成
- 示例：状态查看器和部署助手

### ✅ **质量检查**
- 文件和目录模式混合支持
- 代码格式化、linting、单元测试
- 示例：格式检查、代码质量检查、单元测试

## 快速开始

```bash
# 创建新项目
nix flake init --template github:luochen1990/Nix-FHS#std

# 查看项目状态
nix run .#status

# 运行所有检查
nix flake check

# 进入开发环境
nix develop .#default

# 构建包
nix build .#hello
nix build .#fortune

# 运行应用
nix run .#status
nix run .#deploy local
```

## 实际用例

### 1. 添加新包
在 `packages/my-tool/package.nix` 中创建：
```nix
{ stdenv, lib, ... }:
stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0.0";
  src = ./src;
  meta.description = "My custom tool";
}
```

### 2. 创建 NixOS 模块
在 `nixosModules/my-module/` 中添加：
```nix
# options.nix
{ lib, ... }:
{
  options.my-module.enable = lib.mkEnableOption "My module";
}

# config.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.my-module.enable {
    # 模块配置
  };
}
```

### 3. 系统配置使用
在 `nixosConfigurations/my-host/configuration.nix` 中：
```nix
{ config, lib, pkgs, ... }:
{
  services.my-module.enable = true;

  environment.systemPackages = with pkgs; [ vim git ];
}
```

## 部署

```bash
# 构建 NixOS 系统
nixos-rebuild switch --flake .#example

# 部署到测试环境
nix run .#deploy staging

# 生产环境部署（需要额外配置）
nix run .#deploy production
```

## 最佳实践

1. **遵循约定**：使用标准的目录结构和命名规范
2. **模块化设计**：保持功能独立和可复用
3. **类型安全**：使用 Nix 的类型系统定义选项
4. **测试驱动**：为每个功能添加相应的检查
5. **文档优先**：为复杂功能编写说明文档

## 扩展指南

- **新包**：在 `pkgs/` 下创建目录和 `package.nix`
- **新模块**：在 `modules/` 下创建目录，添加 `options.nix` 和 `config.nix`
- **新配置**：在 `profiles/` 下创建 `configuration.nix`
- **新环境**：在 `shells/` 下创建 `*.nix`
- **新应用**：在 `apps/` 下创建目录和 `default.nix`
- **新检查**：在 `checks/` 下添加文件或目录