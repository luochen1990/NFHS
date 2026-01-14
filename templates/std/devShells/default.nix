{
  pkgs,
  lib,
  ...
}:

pkgs.mkShell {
  name = "default-development-shell";

  buildInputs = with pkgs; [
    # Basic tools
    git
    curl
    wget
    htop
    tree

    # Text processing
    ripgrep
    fzf
    bat
    jq
    yq

    # Nix development
    nixfmt-tree
    deadnix
    statix

    # Useful utilities
    file
    which
    findutils
  ];

  shellHook = ''
    echo "🛠️  Nix FHS Development Environment Ready!"
    echo ""
    echo "📋 Available development shells:"
    echo "  nix develop .#default      - Basic development environment"
    echo "  nix develop .#rust         - Rust development environment"
    echo ""
    echo "🔧 Available apps:"
    echo "  nix run .#status           - Show project status"
    echo "  nix run .#deploy local     - Deploy to local"
    echo ""
    echo "📦 Available packages:"
    echo "  nix build .#hello-fhs      - Build hello package"
    echo "  nix build .#fortune-fhs    - Build fortune package"
    echo ""
    echo "✅ Run checks:"
    echo "  nix flake check            - Run all checks"
  '';

  # Custom environment variables
  FLAKE_FHS_ENV = "development";
  PS1 = "\\[\\033[01;32m\\][nix-fhs-dev]\\[\\033[00m\\]\\$ ";
}
