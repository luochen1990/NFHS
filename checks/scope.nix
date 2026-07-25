{
  pkgs,
  self,
  lib,
  ...
}:
let
  utils' = lib // (import ../lib/list.nix) // (import ../lib/dict.nix) // (import ../lib/file.nix);
  inherit (import ../lib/fhs-lib.nix utils') prepareLib;
  libWithUtils = utils' // { inherit prepareLib; };

  # mkCheck :: String -> AttrSet -> Derivation
  # 统一的 check derivation 生成器，消除各测试文件结尾重复的 fail-check + touch 模板。
  # checks 是一个 attrset，值为 "PASS: ..." 或 "FAIL: ..." 字符串；
  # 任一含 FAIL 时 derivation 构建失败（exit 1）。
  mkCheck =
    name: checks:
    pkgs.runCommand "check-${name}"
      # 通过 derivation 属性引用强制求值所有 check 结果（Nix 惰性求值兜底）
      { checkResults = builtins.toJSON checks; }
      ''
        ${builtins.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: "echo \"${k}: ${v}\"") checks
        )}

        if echo '${builtins.toJSON checks}' | grep -q FAIL; then
          echo "=== Some tests FAILED ==="
          exit 1
        fi

        echo "=== All tests passed ==="
        touch $out
      '';
in
{
  scope = lib.mkScope (pkgs // {
    inherit self lib;
    fhs-modules = import ../lib/fhs-modules.nix libWithUtils;
    flake-fhs = import ../lib/flake-fhs.nix libWithUtils;
    inherit mkCheck;
  });
}
