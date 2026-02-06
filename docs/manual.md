# Flake FHS 使用手册

Flake FHS 是一个 Nix Flake 框架，旨在通过标准化的目录结构自动生成 flake outputs，减少配置文件的维护成本。

## 1. 目录映射机制

框架的核心机制是将文件系统的目录结构直接映射为 Nix flake outputs。

**映射规则表**

| 目录 (别名) | 识别模式 | 生成 Output | 对应的 Nix 命令 |
| :--- | :--- | :--- | :--- |
| [`pkgs`](#pkgs) (`packages`) | `<name>.nix` 或 `<name>/package.nix` | `packages.<system>.<name>` | `nix build .#<name>` |
| [`modules`](#modules) (`nixosModules`) | `<name>/{options.nix,*.nix}` | `nixosModules.<name>` | - |
| [`hosts`](#hosts) (`profiles`) | `<name>/configuration.nix` | `nixosConfigurations.<name>` | `nixos-rebuild --flake .#<name>` |
| [`apps`](#apps) | `<name>.nix` 或 `<name>/package.nix` | `apps.<system>.<name>` | `nix run .#<name>` |
| [`shells`](#shells) (`devShells`) | `<name>.nix` | `devShells.<system>.<name>` | `nix develop .#<name>` |
| `templates` | `<name>/` | `templates.<name>` | `nix flake init ...` |
| [`lib`](#lib) (`utils`) | `<name>.nix` | `lib.<name>` | `nix eval .#lib.<name>` |
| [`checks`](#checks) | `<name>.nix` 或 `<name>/package.nix` | `checks.<system>.<name>` | `nix flake check .#<name>` |

---

## 2. 详细说明

### <span id="pkgs">pkgs/ - 软件包</span>

用于定义项目特有的软件包。

**目录结构**

遵循类似 `nixpkgs` 的 `by-name` 结构，同时支持单文件定义：

```
pkgs/
├── hello.nix            # 简单包 (文件模式)
├── complex-app/         # 复杂包 (目录模式)
│   ├── package.nix      # -> 必须包含此文件
│   └── src/
└── group/               # 包组
    ├── scope.nix        # -> 定义局部作用域
    ├── utils.nix
    └── core/
        └── package.nix
```

**Scope 与 callPackage**

Flake FHS 使用 Nix 的 `callPackage` 机制来构建软件包。所有包定义（无论是 `.nix` 文件还是 `package.nix`）都通过 `callPackage` 构建，因此你可以直接声明所需的依赖。

**Scope (作用域)**

`scope.nix` 文件用于配置 `callPackage` 所使用的 **Scope (上下文包集)**。

*   **作用范围**: `scope.nix` 会影响**同级目录**中的所有包以及**所有子目录**。
*   **约定格式**: `{ pkgs, inputs, ... }: { scope = ...; args = ...; }`

**参数说明**

*   **scope**: 指定用于执行 `callPackage` 的基础包集 (Base Scope)。
    *   例如：`pkgs.python3Packages`。
    *   如果指定了 `scope`，则会**替换**父级的 scope（切断继承）。
    *   如果未指定，则默认**继承**父级的 scope。
*   **args**: 注入到 `callPackage` 的额外参数。
    *   这些参数会作为 **第二个参数** 传递给 `callPackage`。
    *   最终，它们可以作为参数直接传递给包定义函数。

**参数注入**

默认情况下，`callPackage` 的作用域仅包含 `pkgs`。如果你的包需要访问全局参数（如 `self`, `inputs`, `lib`），你需要通过 `scope.nix` 显式注入它们。

例如，注入 `self` 和 `inputs`：

`pkgs/scope.nix`:
```nix
{ pkgs, self, inputs, lib, ... }:
{
  scope = lib.mkScope (pkgs // { inherit self inputs lib; });
}
```

然后你就可以在包定义中使用它们：
```nix
{ stdenv, inputs, ... }: 
stdenv.mkDerivation {
  # ... 使用 inputs.nixpkgs ...
}
```

**继承规则**

*   **只提供 `args`**: **合并**。继承父级 args，并与当前 args 合并。适合注入公共依赖或配置。
*   **提供 `scope`**: **替换**。使用提供的 `scope` 作为新基础。适合切换语言生态（如切换到 Python 环境）。注意：即使替换了 Scope，父级目录定义的 `args` 依然会被继承（除非被同名参数覆盖）。

**示例 1：集成 Python 包 (目录级)**

```
pkgs/
└── python/
    ├── scope.nix      # 定义作用域
    ├── pandas/
    │   └── package.nix
    └── numpy.nix      # 文件模式
```

`pkgs/python/scope.nix`:
```nix
{ pkgs, ... }:
{
  # 替换模式：切换到 Python 包集
  scope = pkgs.python311Packages;
  
  # 可选：同时对该 scope 进行 override
  # args = { ... }; 
}
```

`pkgs/python/numpy.nix`:
```nix
# 这里可以直接请求 buildPythonPackage, pytest 等 Python 生态的包
{ buildPythonPackage, pytest, ... }:

buildPythonPackage {
  pname = "numpy";
  # ...
}
```

**示例 2：Per-Package 注入参数**

你可以在 `package.nix` 旁边放一个 `scope.nix` 来为该特定包注入参数：

`pkgs/my-app/scope.nix`:
```nix
{ ... }: {
  args = {
    enableFeatureX = true;
    customVersion = "1.0.0";
  };
}
```

`pkgs/my-app/package.nix`:
```nix
{ stdenv, enableFeatureX, customVersion }: # 这里可以直接接收注入的参数

stdenv.mkDerivation {
  # ... 使用 enableFeatureX 和 customVersion
}
```

**代码示例**

`pkgs/hello.nix`:
```nix
{ stdenv, fetchurl }:

stdenv.mkDerivation {
  name = "hello-2.10";
  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/hello/hello-2.10.tar.gz";
    sha256 = "0ssi1wiafch70d1viwdv6vjdvc1sr9h3w7v4qhdbbwj3k9j5b3v8";
  };
}
```

---

### <span id="modules">modules/ - NixOS 模块</span>

用于组织可复用的 NixOS 模块。系统将根据目录特征自动分类加载，无需手动维护 `module-list.nix`。

**目录结构与加载逻辑**

框架将目录分为两类：**Guarded** (含 `options.nix`) 和 **Unguarded** (普通目录)。

```
modules/
├── base/                 # Unguarded: 纯组织容器，会递归扫描
│   ├── shell.nix         # -> 自动导入
│   └── users.nix         # -> 自动导入
├── services/
│   └── web-server/       # Guarded: 包含 options.nix
│       ├── options.nix   # -> 总是导入
│       ├── config.nix    # -> 仅当 config.services.web-server.enable = true 时导入
│       └── sub-helper/   # -> 不会被扫描！(递归在此终止)
└── personal/
    └── config.nix        # -> 自动导入
```

**代码示例**

定义一个 Guarded 模块 (`modules/services/web-server`):

1.  `options.nix`: 定义接口。

    **自动嵌套机制**：Flake FHS 会根据目录结构自动将选项嵌套到对应路径下（例如 `services.web-server`），并自动生成 `enable` 选项。你只需定义模块内部的选项字段。

    ```nix
    { lib, ... }:
    {
      options = {
        # 实际生成: options.services.web-server.port
        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
        };
      };
    }
    ```

    上述代码等效于标准 NixOS 模块：
    ```nix
    { lib, ... }:
    {
      options.services.web-server = {
        enable = lib.mkEnableOption "services.web-server";
        port = lib.mkOption { ... };
      };
    }
    ```

2.  `config.nix`: 实现逻辑。默认会被包裹在 `mkIf cfg.enable { ... }` 中。
    ```nix
    { config, pkgs, ... }:
    {
      # 无需手动写 config = lib.mkIf config.services.web-server.enable ...
      systemd.services.web-server = {
        script = "${pkgs.python3}/bin/python -m http.server ${toString config.services.web-server.port}";
      };
    }
    ```

**使用模块**

在 `hosts/my-machine/configuration.nix` 中：

```nix
{
  # modules/ 下的模块已被自动发现并导入
  services.web-server.enable = true;
  services.web-server.port = 9000;
}
```

---

### <span id="hosts">hosts/ - 系统配置</span>

用于定义具体的机器配置（Entrypoints）。

**目录结构**

```
hosts/
├── server-a/
│   └── configuration.nix   # -> nixosConfigurations.server-a
├── laptop/
│   ├── hardware.nix
│   └── configuration.nix   # -> nixosConfigurations.laptop
└── shared/                 # (约定) 存放共享配置
    └── common.nix
```

**代码示例**

`hosts/laptop/configuration.nix`:

```nix
{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../shared/common.nix  # 手动导入共享配置
  ];

  networking.hostName = "laptop";
  environment.systemPackages = [ pkgs.firefox ];
}
```

构建命令：
```bash
nixos-rebuild build --flake .#laptop
```

---

### <span id="apps">apps/ - 应用程序</span>

定义可通过 `nix run` 直接运行的目标。

**目录结构**

`apps/` 目录完全复用 `pkgs/` 的结构与逻辑：支持 `package.nix` 目录模式、`<name>.nix` 文件模式，以及 `scope.nix` 依赖注入。

区别在于：Flake FHS 会自动将构建出的软件包包装为 App 结构。

**自动推断机制**

框架会尝试自动推断程序的入口点。当然，你也可以通过设置 `meta.mainProgram` 来手动指定。推断优先级如下：
1.  `meta.mainProgram` (显式指定)
2.  `pname`
3.  `name` (去除版本号后缀)

**代码示例**

**1. 目录模式 (`apps/deploy/package.nix`)**

```nix
{ writeShellScriptBin }:
writeShellScriptBin "deploy" ''
  echo "Deploying..."
''
```

**2. 文件模式 (`apps/hello.nix`)**

```nix
{ pkgs }:
pkgs.hello
```

运行命令：
```bash
nix run .#deploy
nix run .#hello
```

---

### <span id="shells">shells/ - 开发环境</span>

定义开发环境 (`devShells`)。

**代码示例**

`shells/rust.nix` (映射为 `devShells.<system>.rust`):

```nix
{ pkgs }:
pkgs.mkShell {
  name = "rust-dev";
  buildInputs = with pkgs; [ cargo rustc ];
}
```

`shells/default.nix` (映射为默认的 `nix develop` 环境):

```nix
{ pkgs }:
pkgs.mkShell {
  inputsFrom = [ (import ../pkgs/my-app/package.nix { inherit pkgs; }) ];
}
```

---

### <span id="checks">checks/ - 测试与检查</span>

用于 `nix flake check`。

**目录结构**

`checks/` 目录完全复用 `pkgs/` 的结构与逻辑：支持 `package.nix` 目录模式、`<name>.nix` 文件模式，以及 `scope.nix` 依赖注入。

**重要变更**

Checks 现在通过 `callPackage` 构建，这意味着你不再直接编写 `{ system, pkgs, ... }` 形式的函数，而是编写标准的包定义函数 `{ pkgs, ... }`。如果你需要 `system` 或其他 inputs，请确保通过 `scope.nix` 注入它们（参见[参数注入](#pkgs)章节）。

**代码示例**

假设你已在 `checks/scope.nix` 中注入了 `self` 和 `inputs`。

**1. 文件模式 (`checks/fmt.nix`)**

```nix
{ pkgs, self }: # 需在 scope.nix 中注入 self
pkgs.runCommand "check-fmt" {
  buildInputs = [ pkgs.nixfmt ];
} ''
  nixfmt --check ${self}
  touch $out
''
```

**2. 目录模式 (`checks/integration/package.nix`)**

```nix
{ pkgs, inputs }: # 需在 scope.nix 中注入 inputs
pkgs.runCommand "integration-test" {} ''
  echo "Running tests against ${inputs.nixpkgs.rev}..."
  touch $out
''
```

---

## 🧹 Formatter - 代码格式化

Flake FHS 默认配置了 `formatter` 输出，支持 `nix fmt` 命令。

**默认行为**

Flake FHS 集成了 `treefmt`。它会自动检测根目录下的 `treefmt.nix` 或 `treefmt.toml` 配置文件，并据此生成 formatter。

*   **存在 `treefmt.nix`**: 优先使用。若 `inputs` 中包含 `treefmt-nix`，则通过该库集成；否则直接加载 Nix 配置。
*   **存在 `treefmt.toml`**: 使用该 TOML 文件作为配置。
*   **无配置文件**: 直接使用默认的 `pkgs.treefmt`（运行时可能需要自行查找配置）。

**使用方法**

```bash
# 格式化项目中的所有文件
nix fmt
```

---

### <span id="lib">lib/ - 函数库</span>

定义在 `lib/` 下的函数会被合并，并通过 `pkgs.lib` 在整个 flake 上下文中可用。

**代码示例**

`lib/math.nix`:
```nix
{
  add = a: b: a + b;
}
```

在其他地方使用：
```nix
# anywhere in the flake
{ pkgs, ... }:
{
  # pkgs.lib 包含了自定义的函数
  value = pkgs.lib.math.add 1 2;
}
```

---

## 3. mkFlake 配置

`mkFlake` 函数接受两个参数：上下文 (`inputs`, `self` 等) 和 配置模块。

```nix
flake-fhs.lib.mkFlake { inherit inputs; } {
  # 配置项
}
```

### 常用配置项

| 选项 | 类型 | 默认值 | 说明 |
| :--- | :--- | :--- | :--- |
| `systems` | list | standard systems | 支持的系统架构列表 (x86_64-linux, aarch64-darwin 等) |
| `nixpkgs.config` | attrs | `{ allowUnfree = true; }` | 传递给 nixpkgs 的配置 |
| `layout.roots` | list | `["" "/nix"]` | 项目根目录列表。支持从多个目录聚合内容。 |
| `systemContext` | lambda | `_: {}` | 系统上下文生成器 (`system -> attrs`)。返回的 attrset 中的 `specialArgs` 将被传递给 `nixosSystem`。支持自动合并。 |
| `flake` | attrs | `{}` | 合并到生成的 flake outputs 中。用于手动扩展或覆盖 FHS 生成的内容。 |

### 布局配置 (Layout)

你可以通过 `layout` 选项自定义各类型 output 的源目录。例如：

```nix
layout.packages.subdirs = [ "pkgs" "my-packages" ];
```

这意味着框架将同时扫描 `pkgs/` 和 `my-packages/` 目录来寻找包定义。

## 🔗 最佳实践

### 1. 项目组织

*   **遵循约定**：尽量使用框架默认的目录结构，减少自定义配置。
*   **模块化**：将复杂的系统配置拆分为小的、可复用的模块 (`modules/`)。
*   **按需导出**：利用 `pkgs/default.nix` 隐藏内部辅助包，保持对外接口的整洁。

### 2. 开发流程

*   **快速开始**：总是使用模板 (`nix flake init --template ...`) 来初始化新项目或组件。
*   **持续检查**：养成运行 `nix flake check` 的习惯，配合 `checks/` 目录下的测试用例。
*   **格式化**：使用 `nix fmt` 保持代码风格统一。

### 3. 性能优化

*   **部分加载**：对于拥有大量 NixOS 模块的项目，Flake FHS 的模块加载机制（Guarded Modules）可以显著减少 evaluation 时间。确保将独立的模块放入带有 `options.nix` 的子目录中，这样只有在 `enable = true` 时才会加载其配置。
