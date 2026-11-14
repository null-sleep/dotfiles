#!/bin/bash
# Verify the label setup suffixes subscription models and preserves everything else.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cat >"$tmp/bin/omp" <<'EOF'
#!/bin/bash
case "$*" in
  "config path") printf '%s\n' "$OMP_TEST_DIR" ;;
  "models anthropic --json")
    printf '%s\n' '{"models":[
      {"provider":"anthropic","id":"claude-sonnet-5-5","name":"Claude Sonnet 5.5"},
      {"provider":"anthropic","id":"claude-opus-5-5","name":"Claude Opus 5.5 (sub)"},
      {"provider":"anthropic","id":"claude-haiku-4-5","name":"Claude Haiku 4.5"},
      {"provider":"openrouter","id":"anthropic/claude-sonnet-5.5","name":"Claude Sonnet 5.5"}]}' ;;
  "models openai-codex --json")
    printf '%s\n' '{"models":[
      {"provider":"openai-codex","id":"gpt-6-luna","name":"GPT-6 Luna"},
      {"provider":"openrouter","id":"openai/gpt-6-luna","name":"GPT-6 Luna"}]}' ;;
  "config get modelRoles --json")
    printf '%s\n' '{"value":{"oa-l":"openai-codex/gpt-6.1-sol:xhigh, openai-codex/gpt-6-astra:high","oa-x":["@oa-l","anthropic/claude-mythos-5-2"],"default":"openrouter/openai/gpt-6.1-terra:high"}}' ;;
  "models find gpt-6.1-sol --json")
    printf '%s\n' '{"models":[{"provider":"openrouter","id":"openai/gpt-6.1-sol","name":"GPT-6.1 Sol"}]}' ;;
  "models find gpt-6-astra --json")
    printf '%s\n' '{"models":[{"provider":"openrouter","id":"openai/gpt-6-astra","name":"GPT-6 Astra"}]}' ;;
  "models find claude-mythos-5.2 --json")
    printf '%s\n' '{"models":[{"provider":"openrouter","id":"anthropic/claude-mythos-5.2","name":"Claude Mythos 5.2"}]}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/omp"
export PATH="$tmp/bin:$PATH" OMP_TEST_DIR="$tmp/config"
cat >"$OMP_TEST_DIR/models.yml" <<'EOF'
providers:
  openrouter:
    modelOverrides:
      openrouter/auto-code:
        contextWindow: 1000000
  anthropic:
    modelOverrides:
      claude-haiku-4-5:
        name: My Haiku
        maxTokens: 1234
EOF
chmod 640 "$OMP_TEST_DIR/models.yml"
bash "$root/setup-model-labels.sh"
ruby -ryaml -e '
  path = ARGV.fetch(0)
  providers = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false).fetch("providers")
  raise "unrelated provider changed" unless providers.dig("openrouter", "modelOverrides", "openrouter/auto-code", "contextWindow") == 1_000_000
  raise "openrouter model labelled" if providers.dig("openrouter", "modelOverrides").key?("anthropic/claude-sonnet-5.5")
  raise "openrouter model labelled" if providers.dig("openrouter", "modelOverrides").key?("openai/gpt-6-luna")
  raise "codex suffix missing" unless providers.dig("openai-codex", "modelOverrides", "gpt-6-luna", "name") == "GPT-6 Luna (sub)"
  raise "role-only codex model unlabelled" unless providers.dig("openai-codex", "modelOverrides", "gpt-6.1-sol", "name") == "GPT-6.1 Sol (sub)"
  raise "comma-list role entry unlabelled" unless providers.dig("openai-codex", "modelOverrides", "gpt-6-astra", "name") == "GPT-6 Astra (sub)"
  raise "array role entry unlabelled" unless providers.dig("anthropic", "modelOverrides", "claude-mythos-5-2", "name") == "Claude Mythos 5.2 (sub)"
  o = providers.dig("anthropic", "modelOverrides")
  raise "missing suffix" unless o.dig("claude-sonnet-5-5", "name") == "Claude Sonnet 5.5 (sub)"
  raise "suffix doubled" unless o.dig("claude-opus-5-5", "name") == "Claude Opus 5.5 (sub)"
  raise "custom name replaced" unless o["claude-haiku-4-5"] == {"name" => "My Haiku", "maxTokens" => 1234}
  raise "file mode changed" unless File.stat(path).mode & 0o777 == 0o640
' "$OMP_TEST_DIR/models.yml"
cp "$OMP_TEST_DIR/models.yml" "$tmp/before.yml"
bash "$root/setup-model-labels.sh"
cmp "$tmp/before.yml" "$OMP_TEST_DIR/models.yml"
echo "ok"
