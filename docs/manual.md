# Flake FHS 使用手册

Flake FHS 是一个 Nix flakes 项目结构框架，它通过标准化的目录结构自动生成 flake outputs，让开发者专注于业务逻辑而非配置管理。

## 🚀 快速开始

### 核心映射关系

Flake FHS 建立了文件系统到 flake outputs 的直接映射关系：

**文件路径 → flake output → Nix 子命令**

| 子目录 (别名) | 文件模式 | 特殊文件 | 递归子目录 | 生成的 flake output | Nix 子命令 |
| --- | --- | --- | :---: | --- | --- |
| [`packages`](#dir-pkgs) (`pkgs`) | `<name>/package.nix` | `default.nix` | ✅ | `packages.<system>.<name>` | `nix build .#<name>` |
| [`nixosModules`](#dir-modules) (`modules`) | `<name>/...` | `options.nix`, `default.nix` | ✅ | `nixosModules.<name>` | - |
| [`nixosConfigurations`](#dir-hosts) (`hosts`, `profiles`) | `<name>/configuration.nix` | 无 | ✅ | `nixosConfigurations.<name>` | `nixos-rebuild --flake .#<name>` |
| [`apps`](#dir-apps) | `<name>/package.nix` | `default.nix` | ✅ | `apps.<system>.<name>` | `nix run .#<name>` |
| [`devShells`](#dir-shells) (`shells`) | `<name>.nix` | `default.nix` | ✅ | `devShells.<system>.<name>` | `nix develop .#<name>` |
| [`templates`](#dir-templates) | `<name>/` | `flake.nix` | ❌ | `templates.<name>` | `nix flake init ...` |
| [`lib`](#dir-lib) (`utils`, `tools`) | `<name>.nix` | 无 | ✅ | `lib.<name>` | `nix eval .#lib.<name>` |
| [`checks`](#dir-checks) | `<name>.nix` | `default.nix` | ✅ | `checks.<system>.<name>` | `nix flake check .#<name>` |

### ✨ 核心特性

- **自动发现**：所有 `<name>` 来自文件/目录名，无需手动声明
- **支持多种命名风格**：支持 `packages`, `devShells` 这样跟 flake output 1:1 的子目录命名，同时也支持 `pkgs`, `shells` 这样简短的子目录命名
- **支持多个根目录**：多个根目录中的内容将由 Flake FHS 自动合并

## 📦 <span id="dir-pkgs">pkgs/ - 包定义</span>

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
- 如果 `pkgs/default.nix` 存在，Flake FHS 使用该文件导出的包
- 如果不存在，Flake FHS 自动导出 `pkgs/` 下的所有包

## ⚙️ <span id="dir-modules">modules/ - NixOS 模块</span>

在 nixpkgs 中，modules/ 目录下的模块是由 module-list.nix 手动引入的，但是在 Flake FHS 中，我们会规定 modules/ 目录的结构，并依据此规范自动发现并导入 `modules/` 目录下的所有 NixOS 模块 (生成 flake-outputs.nixosModules.default)，无需手动维护模块列表。

### 目录结构

`modules/` 目录遵循自定义的一套加载机制:

- 将所有子目录按照是否包含 options.nix 文件，分为 guarded (包含) 和 unguarded (不包含) 两类
- 递归地为所有子目录生成 enable 选项, 目录路径决定 options 路径
- 对于 unguarded 目录，默认 enable = true； 对于 guarded 目录，默认 enable = false, 你也可以在 options.nix 中手动覆盖 enable 选项的定义 (WIP)
- 系统将自动导入以下模块:
  a. 所有 unguarded 子目录中的 nix 配置文件 (若目录含 default.nix 则视为叶子模块，仅导入该文件不再递归)
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
# hosts/my-host/configuration.nix
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

**Flake FHS 优势**：
- **自动发现**：无需手动维护模块列表
- **命名约定**：模块选项名称与目录名对应
- **标准化**：与 Nixpkgs 兼容性好, 代码稍加改动就可以贡献到上游
- **高性能**：实现部分加载机制，在存在大量模块时应可以显著减少eval时间

Tips: 模块部分加载机制 的 实现原理详见 [设计文档](./modules-partial-load-design.md)

## 🏗️ <span id="dir-hosts">hosts/ - NixOS 配置</span>

`hosts/` (或 `profiles/`) 目录用于定义完整的 NixOS 系统配置，每个子目录对应一个 `nixosConfigurations` 输出。

### 目录结构

```
hosts/
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
# hosts/desktop/configuration.nix
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

`shared/` 用于存放多个 hosts 之间共享的配置片段：

```nix
# hosts/shared/base-system.nix
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

从 Flake FHS 的角度看，这个目录并不特殊，理论上你可以用任意名字的子目录来做这件事，只要不被 Flake FHS 自动发现为特殊目录即可。

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

## 🚀 <span id="dir-apps">apps/ - 应用程序</span>

`apps/` 目录定义可直接运行的应用程序，每个子目录对应一个 `flake outputs.apps` 项。

**设计说明**：`apps/` 目录与 `pkgs/` 目录使用相同的 `package.nix` 结构。Flake FHS 会自动为每个包生成对应的 `apps` 输出，使用以下规则推断程序入口点（优先级从高到低）：

1. `meta.mainProgram` - 显式指定的程序名
2. `pname` - 包名称（如果存在）
3. `name` 的第一部分 - 去除版本号后的包名（如 `hello-2.10` → `hello`）

这意味着同一个定义可以同时作为 `packages` 和 `apps` 使用，且通常无需显式指定 `meta.mainProgram`。

### 目录结构

```
apps/
├── hello/
│   └── package.nix
├── deploy/
│   ├── package.nix
│   └── deploy.sh
└── backup/
    ├── package.nix
    └── backup.py
```

### 应用定义示例

```nix
# apps/hello/package.nix
{ lib, writeShellScriptBin }:

writeShellScriptBin "hello-app" ''
  #!${writeShellScriptBin}
  echo "Hello from Flake FHS!"
  echo "Current time: $(date)"
''
// {
  meta.description = "A simple hello app";
  # meta.mainProgram 可选，writeShellScriptBin 会自动设置
}
```

**注意**：`writeShellScriptBin` 会自动将脚本名称设置为 `meta.mainProgram`，因此无需手动指定。

对于使用 `mkDerivation` 打包的更复杂应用：

```nix
# apps/deploy/package.nix
{ lib, stdenv, makeWrapper }:

stdenv.mkDerivation {
  pname = "deploy";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp deploy.sh $out/bin/deploy
    chmod +x $out/bin/deploy
  '';

  meta.description = "Deployment helper for Flake FHS projects";
  # meta.mainProgram 可选，会自动从 pname 推断为 "deploy"
}
```

**推断规则**：
- 如果 `pname = "deploy"`，则 `mainProgram` 自动推断为 `"deploy"`
- 如果 `name = "myapp-1.2.3"` 且没有 `pname`，则 `mainProgram` 自动推断为 `"myapp"`
- 显式设置 `meta.mainProgram` 可覆盖自动推断

### 使用方法

```bash
# 运行应用 (使用 apps 输出)
nix run .#hello

# 或者先构建再运行 (使用 packages 输出)
nix build .#hello
./result/bin/hello-app

# 查看所有可用应用和包
nix flake show
```

## 🔧 <span id="dir-shells">shells/ - 开发环境</span>

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
    name = "flake-fhs-dev";

    buildInputs = with pkgs; [
      git
      vim
      curl
      nixfmt
    ];

    shellHook = ''
      echo "🚀 Welcome to Flake FHS development environment!"
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

## 📋 <span id="dir-templates">templates/ - 项目模板</span>

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

## 🛠️ <span id="dir-lib">lib/ - 辅助函数库</span>

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
  # Flake FHS 会将自定义的 lib 注入到 pkgs.lib 中
  xs = lib.list.join [[1 2 3] [4 5]];
}
```

## ✅ <span id="dir-checks">checks/ - 检查和测试</span>

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

Flake FHS 默认配置了 `formatter` 输出，使用 `nixfmt-tree` 作为格式化工具。

```bash
# 格式化项目中的所有 Nix 文件
nix fmt
```

## mkFlake 配置项

`mkFlake` 函数使用 Nix 模块系统来管理配置，提供了类型安全和可组合的配置方式。

### 基本用法

```nix
# 简洁用法（使用默认配置）
flake-fhs.lib.mkFlake { inherit inputs; } { }

# 或直接传入空配置
flake-fhs.lib.mkFlake { inherit inputs; } { }
```

### 配置选项

`mkFlake` 接受两个参数：上下文参数和配置模块。

#### 上下文参数（第一个参数）

| 参数 | 类型 | 描述 | 默认值 |
|------|------|------|--------|
| `self` | attrset | 当前 flake 的引用 | `inputs.self` |
| `inputs` | attrset | 所有 flake 输入 | 必需 |
| `nixpkgs` | attrset | Nixpkgs 输入 | `inputs.nixpkgs` |
| `lib` | attrset | Nix 函数库 | `nixpkgs.lib` |

#### 配置模块选项（第二个参数）

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `systems` | list of str | `lib.systems.flakeExposed` | 支持的系统架构列表 |
| `nixpkgs.config` | attrs | `{ allowUnfree = true; }` | Nixpkgs 配置选项 |
| `layout` | submodule | 见下方说明 | 目录布局配置 |
| `nixosConfigurations.specialArgs` | function | `_: {}` | 传递给 nixosSystem 的 extra specialArgs (`system -> attrs`) |
| `nixosConfigurations.perHost.specialArgs` | function | `_: {}` | 针对特定 host 的 extra specialArgs (`hostName -> attrs`) |
| `flake` | attrs | `{ }` | 额外的 flake outputs（即将支持） |
| `perSystem` | attrs | `{ }` | 每个系统的额外配置（即将支持） |

#### layout 配置项

`layout` 选项控制各个输出类型的目录映射，支持两种形式：

1. **简写形式**：直接指定目录列表
   ```nix
   layout.roots = [ "" "/nix" ]
   ```

2. **完整形式**：使用 `subdirs` 字段
   ```nix
   layout.roots.subdirs = [ "" "/nix" ]
   layout.packages.subdirs = [ "pkgs" "packages" ]
   ```

### 配置示例

#### 基础配置

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs = inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } { };
}
```

#### 完整配置

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
  };

  outputs = inputs@{ flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "x86_64-darwin" ];
      nixpkgs.config = {
        allowUnfree = true;
        permittedInsecurePackages = [ ];
      };
      layout.roots = [ "" "/nix" ];
    };
}
```

#### 多根项目配置

```nix
flake-fhs.lib.mkFlake { inherit inputs; } {
  layout.roots = [ "" "/nix" ];
}
```

### 参数说明

- **systems**: 默认包含 x86_64-linux, x86_64-darwin, aarch64-linux, aarch64-darwin 等主流架构
- **nixpkgs.config**: 全局 Nixpkgs 配置，会影响所有系统上下文中的 pkgs 实例
- **layout.roots**: 指定项目根目录列表，支持多个根目录。空字符串 `""` 表示项目根目录
- **模块系统**: 使用 `lib.evalModules` 实现，提供类型安全和配置验证

## 🔗 最佳实践

### 项目组织

1. **遵循约定**：按照 Flake FHS 的目录结构组织代码
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

