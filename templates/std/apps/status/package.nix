{
  lib,
  writeShellScriptBin,
}:

writeShellScriptBin "status" ''
  set -euo pipefail

  echo "📊 Nix FHS Project Status"
  echo "=========================="
  echo ""
  echo "📦 Available packages:"
  echo "  - hello-fhs: A greeting package"
  echo "  - fortune-fhs: A fortune generator"
  echo ""
  echo "🔧 Development shells:"
  echo "  - default: Basic development environment"
  echo "  - python: Python development environment"
  echo ""
  echo "⚙️  Available apps:"
  echo "  - status: This status app"
  echo "  - deploy: Deployment helper"
  echo ""
  echo "✅ Available checks:"
  echo "  - lint: Linting check"
  echo "  - unit: Unit tests"
  echo ""
  echo "🏗️  NixOS modules:"
  echo "  - my-service: Example service module"
  echo ""
  echo "🖥️  NixOS configurations:"
  echo "  - laptop: Example system configuration"
''
// {
  meta.mainProgram = "status";
  meta.description = "Show project status and available components";
}
