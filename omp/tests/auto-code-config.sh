#!/bin/bash
# Verify the Auto Code setup preserves unrelated model configuration.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cat >"$tmp/bin/omp" <<'EOF'
#!/bin/bash
if [[ "$*" == "config path" ]]; then printf '%s\n' "$OMP_TEST_DIR"; else exit 1; fi
EOF
chmod +x "$tmp/bin/omp"
export PATH="$tmp/bin:$PATH" OMP_TEST_DIR="$tmp/config"
cat >"$OMP_TEST_DIR/models.yaml" <<'EOF'
providers:
  another-provider:
    baseUrl: https://example.invalid
  openrouter:
    modelOverrides:
      another-model:
        contextWindow: 1234
      openrouter/auto-code:
        compat:
          extraBody:
            plugins:
              - id: unrelated-plugin
                enabled: true
              - id: auto-router
                excluded_models: ["openai/example"]
EOF
chmod 640 "$OMP_TEST_DIR/models.yaml"
bash "$root/setup-auto-code.sh"
ruby -ryaml -e '
  path = ARGV.fetch(0)
  data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
  providers = data.fetch("providers")
  raise "unrelated provider changed" unless providers.dig("another-provider", "baseUrl") == "https://example.invalid"
  overrides = providers.dig("openrouter", "modelOverrides")
  raise "unrelated model changed" unless overrides.dig("another-model", "contextWindow") == 1234
  router = overrides.fetch("openrouter/auto-code")
  raise "incorrect transport or limits" unless router["api"] == "openai-completions" && router["contextWindow"] == 1_000_000 && router["maxTokens"] == 32_768
  plugins = router.dig("compat", "extraBody", "plugins")
  raise "unrelated plugin changed" unless plugins.find { |p| p["id"] == "unrelated-plugin" }["enabled"] == true
  auto = plugins.find { |p| p["id"] == "auto-router" }
  raise "existing exclusion changed" unless auto["excluded_models"] == ["openai/example"]
  expected = %w[openai/gpt-6-luna openai/gpt-6.1-terra openai/gpt-6.1-sol anthropic/claude-sonnet-5.5 google/gemini-4-argon google/gemini-4-carbon]
  raise "incorrect pool" unless auto["allowed_models"] == expected
  raise "file mode changed" unless File.stat(path).mode & 0o777 == 0o640
' "$OMP_TEST_DIR/models.yaml"
cp "$OMP_TEST_DIR/models.yaml" "$tmp/before.yaml"
bash "$root/setup-auto-code.sh"
cmp "$tmp/before.yaml" "$OMP_TEST_DIR/models.yaml"
# A malformed plugins entry must fail without touching the existing file.
cat >"$OMP_TEST_DIR/models.yaml" <<'EOF'
providers:
  openrouter:
    modelOverrides:
      openrouter/auto-code:
        compat:
          extraBody:
            plugins: invalid
EOF
cp "$OMP_TEST_DIR/models.yaml" "$tmp/before.yaml"
if bash "$root/setup-auto-code.sh" 2>/dev/null; then
  echo "Malformed plugins unexpectedly accepted" >&2
  exit 1
fi
cmp "$tmp/before.yaml" "$OMP_TEST_DIR/models.yaml"
echo "Auto Code configuration preservation verified"
