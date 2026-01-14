{
  pkgs,
  lib,
  ...
}:

pkgs.mkShell {
  name = "rust-development-shell";

  buildInputs = with pkgs; [
    rustc
    cargo
    rustfmt
    clippy
    rust-analyzer

    # Development tools
    git
    ripgrep
    fd
    tokei

    # Nix development
    nil
    alejandra
  ];

  shellHook = ''
    echo "🦀 Rust Development Environment Ready!"
    echo "Available commands:"
    echo "  cargo build          - Build your Rust project"
    echo "  cargo run            - Run your Rust project"
    echo "  cargo test           - Run tests"
    echo "  cargo clippy         - Run linter"
    echo "  cargo fmt            - Format code"
    echo "  rust-analyzer        - Start language server"
  '';

  # Set environment variables for Rust development
  RUST_BACKTRACE = "1";
  RUST_LOG = "debug";
}
