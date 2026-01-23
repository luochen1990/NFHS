#!/usr/bin/env python3
"""
Template validation for FlakeFHS.

Tests templates with local FlakeFHS to validate current development changes.
Uses local path replacement to test the actual logic being developed.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional


class TestResult(NamedTuple):
    """Simplified test result."""
    name: str
    passed: bool
    message: str
    details: Optional[str] = None


class ValidationResult(NamedTuple):
    """Template validation result."""
    template: str
    passed: bool
    results: List[TestResult]


class TemplateValidator:
    """Validates FlakeFHS templates."""

    EXPECTED_GITHUB_URL = "github:luochen1990/flake-fhs"

    def __init__(self, templates_dir: Path, project_root: Path):
        self.templates_dir = templates_dir
        self.project_root = project_root

    def _run_nix(self, cmd: List[str], cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
        """Run nix command with experimental features."""
        full_cmd = [
            "nix",
            "--extra-experimental-features", "nix-command",
            "--extra-experimental-features", "flakes",
            #"--option", "sandbox", "false",
            #"--option", "allow-dirty", "true",
            *cmd
        ]
        return subprocess.run(full_cmd, cwd=cwd, capture_output=True, text=True, timeout=300)

    def _check_github_url(self, template_path: Path) -> TestResult:
        """Check template uses correct GitHub URL."""
        try:
            content = (template_path / "flake.nix").read_text()
            if self.EXPECTED_GITHUB_URL in content:
                return TestResult("github_url", True, "Template uses correct GitHub URL")
            return TestResult(
                "github_url", False,
                f"Template does not use expected GitHub URL: {self.EXPECTED_GITHUB_URL}"
            )
        except Exception as e:
            return TestResult("github_url", False, f"Error reading template: {e}")

    def _check_flake(self, temp_dir: Path) -> TestResult:
        """Run nix flake check."""
        try:
            result = self._run_nix(["flake", "check", "--no-net", "--quiet"], cwd=temp_dir)
            if result.returncode == 0:
                return TestResult("flake_check", True, "nix flake check passed")

            error_msg = result.stderr.strip()
            return TestResult("flake_check", False, f"nix flake check failed: {error_msg}")
        except Exception as e:
            return TestResult("flake_check", False, f"Error running flake check: {e}")

    def _check_apps_eval(self, temp_dir: Path) -> TestResult:
        """Run nix eval .#apps --json to ensure apps evaluate correctly."""
        try:
            # We use --json to force deep evaluation of the output structure
            # This catches errors that nix flake check might miss if it doesn't deep eval strings
            result = self._run_nix(["eval", ".#apps", "--json"], cwd=temp_dir)
            if result.returncode == 0:
                return TestResult("apps_eval", True, "apps evaluation passed")
            
            error_msg = result.stderr.strip()
            # Truncate error message if too long
            if len(error_msg) > 500:
                error_msg = error_msg[:500] + "..."
            return TestResult("apps_eval", False, f"apps evaluation failed: {error_msg}")
        except Exception as e:
            return TestResult("apps_eval", False, f"Error running apps evaluation: {e}")

    def _create_temp_template(self, template_path: Path, temp_dir: Path) -> TestResult:
        """Create temporary template with local FlakeFHS."""
        try:
            # Copy template files
            for item in template_path.iterdir():
                if item.is_file():
                    shutil.copy2(item, temp_dir / item.name).chmod(0o644)
                else:
                    shutil.copytree(item, temp_dir / item.name)
                    # Fix permissions
                    for root, dirs, files in os.walk(temp_dir / item.name):
                        for d in dirs:
                            os.chmod(os.path.join(root, d), 0o755)
                        for f in files:
                            os.chmod(os.path.join(root, f), 0o644)

            # Replace GitHub URL with local path
            flake_nix = temp_dir / "flake.nix"
            if flake_nix.exists():
                content = flake_nix.read_text()

                # Use absolute path to avoid circular references
                project_root_abs = str(self.project_root.resolve())
                modified = content.replace(self.EXPECTED_GITHUB_URL, f"path:{project_root_abs}")
                flake_nix.write_text(modified)

                if "path:" in modified and self.EXPECTED_GITHUB_URL not in modified:
                    return TestResult("temp_template", True, f"Temporary template created with path:{project_root_abs}")
                return TestResult("temp_template", False, "Failed to replace GitHub URL")
            return TestResult("temp_template", False, "flake.nix not found in template")
        except Exception as e:
            return TestResult("temp_template", False, f"Error creating template: {e}")

    def validate_template(self, template_name: str) -> ValidationResult:
        """Validate a single template."""
        template_path = self.templates_dir / template_name

        if not template_path.exists():
            return ValidationResult(template_name, False, [
                TestResult("template_check", False, f"Template directory not found: {template_path}")
            ])

        results = [
            self._check_github_url(template_path)
        ]

        # Test with local FlakeFHS
        temp_dir = Path(tempfile.mkdtemp(prefix="template-test-"))
        try:
            # Create temporary template
            temp_result = self._create_temp_template(template_path, temp_dir)
            results.append(temp_result)

            if temp_result.passed:
                results.append(self._check_flake(temp_dir))
                results.append(self._check_apps_eval(temp_dir))

        finally:
            # Cleanup
            if temp_dir.exists():
                shutil.rmtree(temp_dir, ignore_errors=True)

        # Overall result: pass if no failures (including flake_check)
        failures = [r for r in results if not r.passed]
        passed = len(failures) == 0

        return ValidationResult(template_name, passed, results)

    def validate_all(self) -> Dict[str, ValidationResult]:
        """Validate all templates."""
        if not self.templates_dir.exists():
            return {"error": ValidationResult("error", False, [
                TestResult("setup", False, f"Templates directory not found: {self.templates_dir}")
            ])}

        template_dirs = [d for d in self.templates_dir.iterdir()
                        if d.is_dir() and not d.name.startswith('.')]

        if not template_dirs:
            return {"error": ValidationResult("error", False, [
                TestResult("setup", False, "No template directories found")
            ])}

        return {d.name: self.validate_template(d.name) for d in template_dirs}


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Validate FlakeFHS templates")

    # Required arguments to avoid path resolution issues
    parser.add_argument("--project-root", type=Path, default='.',
                       help="Path to project root directory")
    parser.add_argument("--templates-dir", type=Path, default='./templates',
                       help="Path to templates directory")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("--template", type=str, help="Validate specific template only")

    args = parser.parse_args()

    # Validate paths exist
    if not args.templates_dir.exists():
        print(f"❌ Templates directory not found: {args.templates_dir}", file=sys.stderr)
        sys.exit(1)

    if not args.project_root.exists():
        print(f"❌ Project root not found: {args.project_root}", file=sys.stderr)
        sys.exit(1)

    # Make paths absolute for reliable operations
    templates_dir = args.templates_dir.resolve()
    project_root = args.project_root.resolve()

    validator = TemplateValidator(templates_dir, project_root)

    # Run validation
    if args.template:
        results = {args.template: validator.validate_template(args.template)}
    else:
        results = validator.validate_all()

    # Output results
    if args.format == "json":
        json_data = {}
        for name, result in results.items():
            json_data[name] = {
                "template": result.template,
                "passed": result.passed,
                "tests": [{"name": t.name, "passed": t.passed, "message": t.message, "details": t.details}
                        for t in result.results]
            }
        print(json.dumps(json_data, indent=2))
    else:
        passed_count = 0
        total_count = 0

        for name, result in results.items():
            if name == "error":
                print(f"❌ {result.results[0].message}")
                continue

            total_count += 1
            status_icon = "✅" if result.passed else "❌"
            print(f"{status_icon} Template: {name}")

            for test in result.results:
                if test.passed:
                    icon = "✅"
                elif test.name == "flake_check" and "sandbox restrictions" in test.message:
                    icon = "⚠️"
                else:
                    icon = "❌"
                print(f"  {icon} {test.name}: {test.message}")
                if test.details:
                    print(f"    {test.details}")

            if result.passed:
                passed_count += 1
            print()

        print(f"Summary: {passed_count}/{total_count} templates passed")
        sys.exit(0 if passed_count == total_count else 1)


if __name__ == "__main__":
    main()
