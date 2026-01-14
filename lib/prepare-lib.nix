# 这是本项目的 lib 引用
lib:
let
  inherit (builtins)
    pathExists
    concatLists
    isAttrs
    isFunction
    elem
    tail
    head
    ;

  inherit (lib)
    filter
    for
    unionFor
    mapFilter
    concatFor
    findFiles
    hasPostfix
    isNonEmptyDir
    lsDirs
    exploreDir
    ;
in
{
  # utils preparation tool function
  prepareLib =
    {
      roots,
      lib, # 这是 nixpkgs 的 lib
      pkgs ? null,
      libSubdirs ? [
        "lib"
        "tools"
        "utils"
      ],
    }:
    let
      files = concatLists (
        exploreDir roots (it: rec {
          into = it.depth == 0 && elem it.name libSubdirs || it.depth >= 1;
          pick = into;
          out = for (findFiles (hasPostfix "nix") it.path) (
            fpath:
            let
              attrs-or-func = import fpath;
            in
            {
              level =
                if isAttrs attrs-or-func then
                  0
                else if elem "more" (it.breadcrumbs ++ [ it.name ]) then
                  2
                else
                  1;
              path = fpath;
            }
          );
        })
      );

      levels = builtins.groupBy (x: "lv${toString x.level}") files;

      # 返回（不依赖的）自定义函数集合
      lv0 = unionFor (levels.lv0 or [ ]) (x: import x.path);
      layer0 = lv0 // lib;

      # 返回（不依赖pkgs的）自定义函数集合，但每个自定义函数都可从 lib 参数中访问（不依赖pkgs的）基础工具函数
      lv1 = unionFor (levels.lv1 or [ ]) (x: import x.path layer1);
      layer1 = lv1 // layer0; # TODO: 命名冲突不覆盖，而是直接报错
      lv10 = lv1 // lv0;

      # 返回（依赖pkgs的）自定义函数集合，但每个自定义函数都可从 lib 参数中访问全量工具函数
      lv2 =
        pkgs:
        let
          myLib = layer2 pkgs; # 提前预备，避免循环中重复创建
        in
        unionFor (levels.lv2 or [ ]) (
          x:
          import x.path (
            # lib/more/ 目录下的文件可以从 pkgs.lib 参数中访问所有函数
            pkgs // { lib = myLib; }
          )
        );
      layer2 = pkgs: lv2 pkgs // layer1; # TODO: 命名冲突不覆盖，而是直接报错
      lv210 = pkgs: lv2 pkgs // lv10;
    in
    # 用户从 prepareLib { ... } 获得的
    # 根据是否给了 pkgs 有所区别: 如果给了 pkgs 则返回全量函数集合；
    # 若没有 pkgs 则返回基础函数集合 以及附带 more 用于加载全量函数集合
    if pkgs != null then lv210 pkgs else { more = pkgs: lv2 pkgs; } // lv10;
}
