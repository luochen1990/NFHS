# © Copyright 2025 罗宸 (luochen1990@gmail.com, https://lambda.lc)
#
# 职责: flake-fhs lib 纯函数单元测试
#
# 维护原则:
#   1. 只测纯函数 — 文件系统/模块系统函数由 checks/ 集成测试覆盖
#   2. 跳过 trivial wrapper — 对 builtins 的直接封装不测
#   3. 属性测试优先 — 能抽象出不变量的, 用 map 多输入 + 一个 expected
#      (代码中以 "# 属性:" 注释标记, 例: powerset 2^n, trimPath 归一化)
#   4. 正向与负向分离 — 正向用 runTests {expr, expected};
#      负向 (应 throw) 用 mustThrow + tryEval 过滤 leaks
#   5. 直接 import — mergedLib 中 nixpkgs 会覆盖同名函数 (如 hasSuffix)

{ pkgs, lib, ... }:
let
  inherit (lib) debug generators filterAttrs attrNames range;

  # 直接 import, 绕过 mergedLib 的 name override
  fileLib = import ../lib/file.nix;
  listLib = import ../lib/list.nix;
  dictLib = import ../lib/dict.nix;
  pkgTools = import ../lib/pkg-tools.nix lib;

  # ── 正向测试: expr 的值应等于 expected ──
  positive = debug.runTests (

    # ──────────────────────────────────────────────
    # dict.nix — 字典操作
    # ──────────────────────────────────────────────
    {
      # disjoint: 基本正反例
      testDisjoint_true = {
        expr = dictLib.disjoint { a = 1; } { b = 2; };
        expected = true;
      };
      testDisjoint_false = {
        expr = dictLib.disjoint { a = 1; } { a = 2; };
        expected = false;
      };

      # 属性: 对称性 — disjoint a b == disjoint b a
      testDisjoint_symmetric = {
        expr =
          let
            a = { x = 1; };
            b = { y = 2; };
            c = { x = 3; };
          in
          [
            (dictLib.disjoint a b)
            (dictLib.disjoint b a)
            (dictLib.disjoint a c)
            (dictLib.disjoint c a)
          ];
        expected = [ true true false false ];
      };

      # merge2: 正常不相交合并
      testMerge2_basic = {
        expr = dictLib.merge2 { a = 1; } { b = 2; };
        expected = { a = 1; b = 2; };
      };

      # 属性: 不相交合并保持元素数 — length(merge2 a b) == length(a) + length(b)
      testMerge2_cardinality = {
        expr =
          let
            a = { x = 1; y = 2; z = 3; };
            b = { p = 4; q = 5; };
          in
          builtins.length (attrNames (dictLib.merge2 a b));
        expected = 5; # 3 + 2
      };

      # merge: 多元素不相交并
      testMerge_basic = {
        expr = dictLib.merge [ { a = 1; } { b = 2; } { c = 3; } ];
        expected = { a = 1; b = 2; c = 3; };
      };

      # unionFor: foldMap 语义
      testUnionFor_basic = {
        expr = dictLib.unionFor [ "a" "b" ] (k: { ${k} = 1; });
        expected = { a = 1; b = 1; };
      };

      # 属性: 空列表 foldMap → 空 attrset (幺元)
      testUnionFor_empty = {
        expr = dictLib.unionFor [ ] (k: { ${k} = 1; });
        expected = { };
      };

      # unionForItems: 同时遍历 key 和 value
      testUnionForItems_basic = {
        expr = dictLib.unionForItems { x = 10; y = 20; } (k: v: { ${k} = v * 2; });
        expected = { x = 20; y = 40; };
      };
    }

    # ──────────────────────────────────────────────
    # list.nix — 列表操作
    # ──────────────────────────────────────────────
    // {
      # forFilter: null 被过滤, 非 null 值保留
      testForFilter_partialNull = {
        expr = listLib.forFilter [ 1 2 3 ] (x: if x > 1 then x * 10 else null);
        expected = [ 20 30 ];
      };
      # 属性: 结果长度永远 <= 输入长度
      testForFilter_lengthBounded = {
        expr =
          let
            inputs = [ [ ] [ 1 ] [ 1 2 3 ] [ 1 2 3 4 5 ] ];
            f = x: if x > 1 then x else null;
          in
          map (xs: builtins.length (listLib.forFilter xs f)) inputs;
        expected = [ 0 0 2 4 ]; # <= [ 0 1 3 5 ]
      };

      # powerset: 递归基例
      testPowerset_empty = {
        expr = listLib.powerset [ ];
        expected = [ [ ] ];
      };

      # 属性: length (powerset xs) == 2^n (覆盖 n=0..5)
      testPowerset_count_2powN = {
        expr = map (n: builtins.length (listLib.powerset (range 1 n))) [ 0 1 2 3 4 5 ];
        expected = [ 1 2 4 8 16 32 ];
      };
    }

    # ──────────────────────────────────────────────
    # file.nix — 纯字符串/路径操作 (不含文件系统函数)
    # ──────────────────────────────────────────────
    // {
      # hasSuffix: 匹配/不匹配
      testHasSuffix_match = {
        expr = fileLib.hasSuffix ".nix" "foo.nix";
        expected = true;
      };
      testHasSuffix_noMatch = {
        expr = fileLib.hasSuffix ".nix" "foo.txt";
        expected = false;
      };

      # elemAt: 正索引
      testElemAt_positive = {
        expr = fileLib.elemAt 1 [ 10 20 30 ];
        expected = 20;
      };

      # 属性: 负索引等价正索引 — elemAt (-1) xs == elemAt (length-1) xs
      testElemAt_negative_equivalence = {
        expr = map (xs: fileLib.elemAt (-1) xs) [ [ 1 ] [ 1 2 ] [ 1 2 3 ] ];
        expected = [ 1 2 3 ];
      };

      # 属性: 首尾斜杠归一化 — 4 种写法产生同一结果
      testTrimPath_normalization = {
        expr = map fileLib.trimPath [ "/foo/bar/" "/foo/bar" "foo/bar/" "foo/bar" ];
        expected = [ "foo/bar" "foo/bar" "foo/bar" "foo/bar" ];
      };
    }

    # ──────────────────────────────────────────────
    # pkg-tools.nix — 包工具
    # ──────────────────────────────────────────────
    // {
      # 属性: 优先级链 — meta.mainProgram > pname > parseDrvName(name)
      # 每级一个测试, 确保正确短路到正确的分支
      testInferMainProgram_fromMeta = {
        expr = pkgTools.inferMainProgram {
          meta.mainProgram = "cli";
          pname = "pkg";
          name = "pkg-1.0";
        };
        expected = "cli";
      };
      testInferMainProgram_fromPname = {
        expr = pkgTools.inferMainProgram {
          pname = "mypkg";
          name = "mypkg-1.0";
        };
        expected = "mypkg";
      };
      # 属性: parseDrvName 在 "第一个后面不跟字母的 -" 处分割版本号
      # hello-2.10 -> hello
      testInferMainProgram_fromName_simple = {
        expr = pkgTools.inferMainProgram { name = "hello-2.10"; };
        expected = "hello";
      };
      # apache-httpd-2.0.48 -> apache-httpd (-httpd 后面跟字母, 不分割)
      testInferMainProgram_fromName_multiSegment = {
        expr = pkgTools.inferMainProgram { name = "apache-httpd-2.0.48"; };
        expected = "apache-httpd";
      };

      # mkScope: 注入 callPackage
      testMkScope_hasCallPackage = {
        expr = builtins.hasAttr "callPackage" (pkgTools.mkScope { });
        expected = true;
      };
    }
  );

  # 负向测试: 以下表达式都应当 throw; leaks = 应 throw 但未 throw 的 (bug)
  mustThrow = {
    merge2-keyOverlap = dictLib.merge2 { a = 1; } { a = 2; };
    merge-keyOverlap = dictLib.merge [ { a = 1; } { a = 2; } ];
    hasSuffix-noDotPrefix = fileLib.hasSuffix "nix" "foo.nix";
    mkScope-funcInput = pkgTools.mkScope (x: x);
  };
  leaks = attrNames (filterAttrs (_: e: (builtins.tryEval e).success) mustThrow);

in
if positive == [ ] && leaks == [ ] then
  pkgs.runCommand "lib-unit-tests" { } "touch $out"
else
  builtins.throw ''
    ┌─ positive failures:
    ${generators.toPretty { multiline = true; } positive}
    └─ unexpected leaks (should have thrown): ${toString leaks}
  ''
