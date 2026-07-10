# 验证正确性: 集成测试 (template-validation) + nix flake check
check:
    ./checks/template-validation/validators.py && nix flake check

# Nix 代码静态检查: deadnix (死代码) + statix (反模式); --fix 触发原地自动修复
# 用法: just lint | just lint --fix | just lint lib | just lint --fix lib/file.nix
lint *ARGS:
    ./scripts/lint {{ARGS}}
