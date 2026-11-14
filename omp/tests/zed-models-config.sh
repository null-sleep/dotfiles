#!/bin/bash
# Verify the Zed omp scope covers every role selector shape and stays valid YAML.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cat >"$tmp/bin/omp" <<'EOF'
#!/bin/bash
case "$*" in
  "config path") printf '%s\n' "$OMP_TEST_DIR" ;;
  "config get modelRoles --json")
    printf '%s\n' '{"value":{
      "default": "openrouter/openai/gpt-6.1-terra:high",
      "smol": "@luna",
      "luna": "openrouter/openai/gpt-6-luna@azure:xhigh",
      "loop": "@loop",
      "dangling": "@missing",
      "opus": "anthropic/claude-opus-5-5:high",
      "carbon": "openrouter/google/gemini-4-carbon@google-vertex/global/flex:high",
      "list": "openrouter/openai/gpt-6-luna-pro:high, openrouter/z-ai/glm-5.3:max",
      "array": ["openrouter/moonshotai/kimi-k3.1-pro", "@opus:low"],
      "fuzzy": "gpt-6-astra-pr:high",
      "odd": "custom/model\"q\\s",
      "web": "web/perplexity"}}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/omp"
export PATH="$tmp/bin:$PATH" OMP_TEST_DIR="$tmp/config"
bash "$root/setup-zed-models.sh" >/dev/null
ruby -ryaml -e '
  data = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
  got = data.fetch("enabledModels")
  want = [
    "*/*claude-opus-5[.-]5",
    "*/*gemini-4-carbon",
    "*/*glm-5[.-]3",
    "*/*gpt-6-luna",
    "*/*gpt-6-luna-pro",
    "*/*gpt-6[.-]1-terra",
    "*/*kimi-k3[.-]1-pro",
    "*/*model\"q\\s",
    "gpt-6-astra-pr",
  ]
  raise "patterns: got #{got.inspect}" unless got.sort == want.sort
  raise "bedrock not disabled" unless data.fetch("disabledProviders") == ["amazon-bedrock", "bedrock-mantle"]
' "$OMP_TEST_DIR/zed-models.yml"
echo "ok"
