# Nix FHS 使用手册

Nix FHS 是一个 Nix flakes 项目结构框架，它通过标准化的目录结构自动生成 flake outputs，让开发者专注于业务逻辑而非配置管理。

## 🚀 快速开始

### 核心映射关系

Nix FHS 建立了文件系统到 flake outputs 的直接映射关系：

**文件路径 → flake output → Nix 子命令**

| 文件路径  | 生成的 flake output  |  Nix 子命令         |
| ------------- | ------------------ | ------------------------ |
| `pkgs/<name>/package.nix` (或 `packages/`)      | `packages.<system>.<name>`                   | `nix build .#<name>`               |
| `modules/<name>/...` (或 `nixosModules/`)   | `nixosModules.<name>`  | - |
| `profiles/<name>/configuration.nix` (或 `nixosConfigurations/`, `hosts/`)   | `nixosConfigurations.<name>`  | `nixos-rebuild --flake .#<name>`    |
| `apps/<name>/default.nix`      | `apps.<system>.<name>`                       | `nix run .#<name>`                 |
| `shells/<name>.nix` (或 `devShells/`) | `devShells.<system>.<name>`                  | `nix develop .#<name>`             |
| `templates/<name>/`    | `templates.<name>`                           | `nix flake init --template <url>#<name>` |
| `lib/<name>.nix` (或 `utils/`, `tools/`)      | `lib.<name>`                                 | `nix eval .#lib.<name>`            |
| `checks/<name>.nix` 或 `checks/<path>/default.nix` | `checks.<system>.<name>` (路径 `/` 转为 `-`) | `nix flake check .#<name>`            |

### ✨ 核心特性

- **自动发现**：所有 `<name>` 来自文件/目录名，无需手动声明
- **支持多种命名风格**：支持 `packages`, `devShells` 这样跟 flake output 1:1 的子目录命名，同时也支持 `pkgs`, `shells` 这样简短的子目录命名
- **支持多个根目录**：多个根目录中的内容将由 Nix FHS 自动合并

## 📦 pkgs/ - 包定义

`pkgs/<name>/` 目录遵循 **nixpkgs** 项目的 `pkgs/by-name/xx/<name>/` 结构规范，入口文件统一为 `package.nix`。

### 目录结构示例

```
pkgs/
├── hello/
│   └── package.nix
├── my-custom-tool/
│   ├── package.nix
│   └── src/
│       └── main.c
└── default.nix  # 可选：控制包的可见性
```

### 包定义示例

```nix
# pkgs/hello/package.nix
{ stdenv, fetchurl }:

stdenv.mkDerivation {
  name = "hello-2.10";
  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/hello/hello-2.10.tar.gz";
    sha256 = "0ssi1wiafch70d1viwdv6vjdvc1sr9h3w7v4qhdbbwj3k9j5b3v8";
  };
  meta = {
    description = "A program that produces a familiar, friendly greeting";
  };
}
```

### 🔐 控制包的可见性 (WIP)

在某些情况下，您可能希望控制哪些包对外暴露。例如，包 A 依赖 B、C、D，但您只想对外暴露包 A。

创建 `pkgs/default.nix` 文件来精确控制导出的包：

```nix
# pkgs/default.nix
{
  # 只导出这些包到 flake outputs
  hello = import ./hello;
  my-public-tool = import ./my-custom-tool;

  # 以下包不会出现在 flake outputs 中
  # internal-dep = import ./internal-dep;
}
```

**工作原理**：
- 如果 `pkgs/default.nix` 存在，Nix FHS 使用该文件导出的包
- 如果不存在，Nix FHS 自动导出 `pkgs/` 下的所有包

## ⚙️ modules/ - NixOS 模块

在 nixpkgs 中，modules/ 目录下的模块是由 module-list.nix 手动引入的，但是在 Nix FHS 中，我们会规定 modules/ 目录的结构，并依据此规范自动发现并导入 `modules/` 目录下的所有 NixOS 模块 (生成 flake-outputs.nixosModules.default)，无需手动维护模块列表。

### 目录结构

`modules/` 目录遵循自定义的一套加载机制:

- 将所有子目录按照是否包含 options.nix 文件，分为 guarded (包含) 和 unguarded (不包含) 两类
- 递归地为所有子目录生成 enable 选项, 目录路径决定 options 路径
- 对于 unguarded 目录，默认 enable = true； 对于 guarded 目录，默认 enable = false, 你也可以在 options.nix 中手动覆盖 enable 选项的定义 (WIP)
- 系统将自动导入以下模块:
  a. 所有 unguarded 子目录中的 nix 配置文件
  b. 所有 guarded 子目录中的 options.nix 配置文件
  c. 所有 enable = true 的 guarded 子目录中的 nix 配置文件

示范:

```
modules/
├── services/
│   └── vaultwarden/
│       ├── options.nix
│       ├── config.nix
│       └── more-config.nix
├── programs/
│   └── hello/
│       ├── options.nix
│       └── config.nix
└── personal/
    └── config.nix
```

若用户配置为:

```nix
{
  services.vaultwarden.enable = true;
}
```

则将被自动导入的模块文件为:

- modules/services/vaultwarden/options.nix
- modules/services/vaultwarden/config.nix
- modules/services/vaultwarden/more-config.nix
- modules/programs/hello/options.nix
- modules/personal/config.nix

(Tips: 由于 modules/programs/hello/ 为 guarded 目录，且 enable = false，因此只有其 options.nix 文件被导入，而该目录下的 config.nix 文件则不会被导入)

### 目录结构

### 模块定义示例

modules/services/my-service/options.nix:

```nix
{ config, lib, pkgs, ... }:
with lib;
{
  # 默认会生成 enable, 无需手动定义
  # enable = lib.mkEnableOption "My custom service";

  # 默认会生成到 services.my-service 选项路径下, 无需手动定义前缀
  port = lib.mkOption {
    type = lib.types.port;
    default = 8080;
    description = "Port on which my-service should listen";
  };

  package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.my-service;
    description = "My service package to use";
  };
}
```

modules/services/my-service/config.nix:

```nix
{ config, lib, pkgs, ... }:
{
  # 默认会被包裹在 mkIf cfg.enable {} 中，无需手动实现
  config = {
    systemd.services.my-service = {
      description = "My Custom Service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/my-service --port ${toString cfg.port}";
        Restart = "always";
      };
    };
  };
}
```

### 使用模块

在其他 NixOS 配置中使用：

```nix
# profiles/my-host/configuration.nix
{
  # 模块会被自动导入，无需手动编写
  # imports = [
  #   ../modules/services/my-service/options.nix
  #   ../modules/services/my-service/config.nix
  # ];

  services.my-service = {
    enable = true;
    port = 9090;
  };
}
```

**Nix FHS 优势**：
- **自动发现**：无需手动维护模块列表
- **命名约定**：模块选项名称与目录名对应
- **标准化**：与 Nixpkgs 兼容性好, 代码稍加改动就可以贡献到上游
- **高性能**：实现部分加载机制，在存在大量模块时应可以显著减少eval时间

Tips: 模块部分加载机制 的 实现原理详见 [设计文档](./modules-partial-load-design.md)

## 🏗️ profiles/ - NixOS 配置

`profiles/` 目录用于定义完整的 NixOS 系统配置，每个子目录对应一个 `nixosConfigurations` 输出。

### 目录结构

```
profiles/
├── server/
│   └── configuration.nix
├── desktop/
│   ├── hardware-configuration.nix
│   └── configuration.nix
├── laptop/
│   ├── hardware-configuration.nix
│   └── configuration.nix
└── shared/
    ├── base-system.nix
    ├── networking.nix
    └── users.nix
```

### 配置定义示例

```nix
# profiles/desktop/configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # 共享配置
    ../shared/base-system.nix
    ../shared/networking.nix
    ../shared/users.nix
  ];

  # 桌面特定配置
  services.xserver.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    firefox
    libreoffice
    gimp
  ];
}
```

### 📁 shared/ 目录

`shared/` 用于存放多个 profiles 之间共享的配置片段：

```nix
# profiles/shared/base-system.nix
{ config, lib, pkgs, ... }:

{
  # 基础系统配置
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # 基础软件包
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
  ];
}
```

`shared/` 目录中的配置需要由用户在 configuration.nix 中手动引入.

从 Nix FHS 的角度看，这个目录并不特殊，理论上你可以用任意名字的子目录来做这件事，只要不被 Nix FHS 自动发现为特殊目录即可。

### 使用方法

```bash
# 构建桌面系统
nixos-rebuild build --flake .#desktop

# 构建服务器系统
nixos-rebuild build --flake .#server
```

**设计理念**：
- **模块化**：共享配置与特定配置分离
- **复用性**：通过 `shared/` 减少代码重复
- **一致性**：所有配置遵循相同结构

## 🚀 apps/ - 应用程序

`apps/` 目录定义可直接运行的应用程序，每个子目录对应一个 `flake outputs.apps` 项。

### 目录结构

```
apps/
├── hello/
│   ├── default.nix
│   └── hello.py
├── deploy/
│   ├── default.nix
│   └── deploy.sh
└── backup/
    ├── default.nix
    └── backup.py
```

### 应用定义示例

```nix
# apps/hello/default.nix
{ pkgs }:

{
  type = "app";
  program = toString (pkgs.writeScriptBin "hello-app" ''
    #!${pkgs.runtimeShell}
    echo "Hello from Nix FHS!"
    python3 ${./hello.py}
  '');
}
```

```python
# apps/hello/hello.py
#!/usr/bin/env python3
import datetime

print(f"Current time: {datetime.datetime.now()}")
print("This is a Python application packaged with Nix FHS!")
```

### 使用方法

```bash
# 运行应用
nix run .#hello

# 查看所有可用应用
nix flake show
```

## 🔧 shells/ - 开发环境

`shells/` 目录定义开发环境，每个 `.nix` 文件对应一个 `flake outputs.devShells` 项。

### 目录结构

```
shells/
├── default.nix
├── python.nix
└── rust.nix
```

### 开发环境定义示例

```nix
# shells/default.nix
{ pkgs }:

{
  # 默认开发环境
  default = pkgs.mkShell {
    name = "nix-fhs-dev";

    buildInputs = with pkgs; [
      git
      vim
      curl
      nixfmt
    ];

    shellHook = ''
      echo "🚀 Welcome to Nix FHS development environment!"
      echo "Available commands: git, vim, curl, nixfmt"
    '';
  };
}
```

```nix
# shells/rust.nix
{ pkgs }:

pkgs.mkShell {
  name = "rust-dev";

  buildInputs = with pkgs; [
    rustc
    cargo
    rust-analyzer
    clippy
  ];

  shellHook = ''
    echo "🦀 Rust development environment ready!"
    cargo --version
  '';
}
```

### 使用方法

```bash
# 进入默认开发环境
nix develop

# 进入特定开发环境
nix develop .#rust

# 在开发环境中运行命令
nix develop .#python --command python --version
```

## 📋 templates/ - 项目模板

`templates/` 目录提供项目模板，用于快速初始化新项目。

### 目录结构

```
templates/
├── simple-python/
│   ├── flake.nix
│   ├── README.md
│   └── src/
│       └── main.py
├── rust-cli/
│   ├── flake.nix
│   ├── Cargo.toml
│   └── src/
│       └── main.rs
└── nixos-module/
    ├── flake.nix
    └── modules/
        └── example/
            └── options.nix
```

### 使用方法

```bash
# 使用模板创建新项目
nix flake init --template .#simple-python
nix flake init --template .#rust-cli

# 查看可用模板
nix flake show
```

## 🛠️ lib/ - 辅助函数库

`lib/` (或 `utils/`, `tools/`) 目录定义可在其他地方引用的辅助函数和工具。这些函数会被合并到 `flake outputs.lib` 中，并注入到 `pkgs.lib` 中以便在其他地方使用。

### 目录结构

```
lib/
├── list.nix
└── file.nix
```

### 函数库示例

```nix
# lib/list.nix
{
  join = xs: builtins.concatList xs
}
```

### 使用方法

在 nixosConfigurations.nix 或其他模块中使用：

```nix
{ lib, ...}:
{
  # Nix FHS 会将自定义的 lib 注入到 pkgs.lib 中
  xs = lib.list.join [[1 2 3] [4 5]];
}
```

## ✅ checks/ - 检查和测试

`checks/` 目录支持文件模式和目录模式的混合结构：

```
checks/
├── fmt.nix                          → checks.<system>.fmt
├── unit/                             # namespace
│   └── string-utils/                 # name
│       └── default.nix               → checks.<system>."unit/string-utils"
└── integration/                      # namespace
    └── api-tests/                    # name
        └── default.nix               → checks.<system>."integration/api-tests"
```

### 设计规则

- **文件模式**: 顶层 `.nix` 文件（`default.nix` 除外）
- **目录模式**: 递归查找包含 `default.nix` 的子目录
- **命名空间**: 不包含 `default.nix` 的目录用于组织
- **优先级**: 文件优先于目录，避免名称冲突

### 检查定义示例

`checks/fmt.nix`:
```nix
{ pkgs, lib, ... }:

pkgs.runCommand "lint-check" {
  nativeBuildInputs = [ pkgs.nixfmt-tree ];
} ''
  echo "🔍 Running format checks..."
  treefmt --fail-on-change
  touch $out
''
```

### 使用方法

```bash
# 运行所有检查
nix flake check

# 运行特定检查
nix flake check .#lint
nix flake check .#unit-string-utils

# 查看所有检查
nix flake show
```

### 优先级处理

同时存在 `checks/test.nix` 和 `checks/test/default.nix` 时，文件模式优先。

## 🧹 Formatter - 代码格式化

Nix FHS 默认配置了 `formatter` 输出，使用 `nixfmt-tree` 作为格式化工具。

```bash
# 格式化项目中的所有 Nix 文件
nix fmt
```

## mkFlake 配置项

`mkFlake` 函数接受以下配置参数：

### 必需参数

| 参数 | 类型 | 描述 |
|------|------|------|
| `self` | attrset | 当前 flake 的引用 |
| `nixpkgs` | attrset | Nixpkgs 输入 |

### 可选参数

| 参数 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `roots` | list | `[ ./. ]` (以及 `./nix` 若存在) | 项目根目录列表，支持多根项目结构 |
| `inputs` | attrset | `{ }` | 其他 flake 输入 |
| `lib` | attrset | `nixpkgs.lib` | Nix 函数库，默认从 nixpkgs.lib 获取 |
| `supportedSystems` | list | `lib.systems.flakeExposed` | 支持的系统架构列表 |
| `nixpkgsConfig` | attrset | `{ allowUnfree = true; }` | Nixpkgs 配置选项 |

### 参数说明

- **roots**: 指定项目根目录列表，支持多个根目录。默认包含项目根目录，如果存在 `nix/` 目录也会自动包含。
- **lib**: Nix 函数库，默认值为 `nixpkgs.lib`，通常无需手动指定
- **supportedSystems**: 默认包含 x86_64-linux, x86_64-darwin, aarch64-linux, aarch64-darwin 等主流架构
- **nixpkgsConfig**: 全局 Nixpkgs 配置，会影响所有系统上下文中的 pkgs 实例

## 🔗 最佳实践

### 项目组织

1. **遵循约定**：按照 Nix FHS 的目录结构组织代码
2. **保持简洁**：每个文件专注单一职责
3. **文档先行**：为复杂功能编写说明文档

### 开发流程

1. **快速开始**：使用模板快速创建项目
2. **增量开发**：边开发边运行 `nix flake check`
3. **持续集成**：利用 `checks/` 确保代码质量

### 性能优化

1. **按需导出**：使用 `pkgs/default.nix` 控制包可见性
2. **共享依赖**：通过 `profiles/shared/` 减少重复
3. **模块化设计**：保持模块的独立性, 添加 options.nix 以支持部分加载

