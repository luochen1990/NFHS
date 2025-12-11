# .fun.nix 文件属于基础部分，仅依赖builtins 进行定义，不依赖 lib 因此也不需要初始化
# .lib.nix 文件依赖 nixpkgs.lib 因此需要初始化
# .libx.nix 文件依赖 nixpkgs.lib 和 nixpkgs.pkgs 因此需要初始化
# .fhs.fun.nix 文件需要额外的 lib, nixpkgs, inputs 参数
let
  inherit (import ./file.fun.nix) findFiles hasPostfix;
  inherit (import ./dict.fun.nix) unionFor;

  # Basic tool functions (no external dependencies)
  basicTools = unionFor (findFiles (hasPostfix "fun.nix") ./.) (fname:
    if builtins.baseNameOf fname == "fhs.fun.nix" then {} else import fname
  );

  useLib =
    lib:
    {
      usePkgs =
        pkgs: unionFor (findFiles (hasPostfix "libx.nix") ./.) (fname: import fname { inherit lib pkgs; });
    }
    // unionFor (findFiles (hasPostfix "lib.nix") ./.) (fname: import fname { inherit lib; });
in
{
  inherit useLib;
} // basicTools // {
  # mkFlake needs external dependencies, provide a wrapper function
  mkFlake = args:
    let
      fhsModule = import ./fhs.fun.nix {
        inherit (args) lib nixpkgs inputs;
        utils' = basicTools // { inherit useLib; };
      };
    in
    fhsModule.mkFlake (args // {
      # Ensure required args are available
      self = args.self or (throw "mkFlake requires 'self' argument");
      lib = args.lib or (throw "mkFlake requires 'lib' argument");
      nixpkgs = args.nixpkgs or (throw "mkFlake requires 'nixpkgs' argument");
      inputs = args.inputs or {};
    });
}