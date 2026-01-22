{
  lib,
  writeShellScriptBin,
}:

writeShellScriptBin "deploy" ''
  set -euo pipefail

  # Simple deployment simulation
  echo "🚀 Deploying Nix FHS project..."
  echo ""

  if [ $# -eq 0 ]; then
    echo "Usage: deploy <target>"
    echo "Available targets:"
    echo "  - local: Deploy to local system"
    echo "  - staging: Deploy to staging environment"
    echo "  - production: Deploy to production"
    exit 1
  fi

  target="''${1:-local}"
  echo "📋 Target: $target"

  # Simulate deployment steps
  echo "🔍 Validating configuration..."
  sleep 1

  echo "📦 Building packages..."
  sleep 1

  echo "🔄 Deploying services..."
  sleep 1

  echo "✅ Deployment to $target completed successfully!"
''
// {
  meta.mainProgram = "deploy";
  meta.description = "Deployment helper for Nix FHS projects";
}
