#!/bin/bash
# Configure the repo-owned Auto Code model pool without replacing other models.
set -euo pipefail

config_dir="$(omp config path)"
mkdir -p "$config_dir"

# Let OMP migrate legacy JSON before creating an override YAML of our own.
if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" && -e "$config_dir/models.json" ]]; then
  omp models find auto-code --json >/dev/null
  if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" ]]; then
    echo "Error: OMP did not migrate $config_dir/models.json; Auto Code setup stopped." >&2
    exit 1
  fi
fi

ruby -ryaml -e '
  dir = ARGV.fetch(0)
  yml = File.join(dir, "models.yml")
  yaml = File.join(dir, "models.yaml")
  path = File.exist?(yml) || !File.exist?(yaml) ? yml : yaml
  raise "#{path}: refusing to replace a symlink" if File.symlink?(path)
  pool = %w[
    openai/gpt-6-luna
    openai/gpt-6.1-terra
    openai/gpt-6.1-sol
    anthropic/claude-sonnet-5.5
    google/gemini-4-argon
    google/gemini-4-carbon
  ]

  def mapping(parent, key, path)
    value = parent[key]
    raise "#{path}: #{key} must be a mapping" unless value.nil? || value.is_a?(Hash)
    parent[key] ||= {}
  end

  File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX)
    source = File.exist?(path) ? File.read(path) : ""
    data = source.empty? ? {} : YAML.safe_load(source, permitted_classes: [], aliases: false)
    raise "#{path}: expected a YAML mapping" unless data.is_a?(Hash)
    before = Marshal.dump(data)
    provider = mapping(mapping(data, "providers", path), "openrouter", path)
    overrides = mapping(provider, "modelOverrides", path)
    model = mapping(overrides, "openrouter/auto-code", path)
    compat = mapping(model, "compat", path)
    body = mapping(compat, "extraBody", path)
    plugins = body["plugins"]
    raise "#{path}: plugins must be an array" unless plugins.nil? || plugins.is_a?(Array)
    plugins ||= []
    # OpenRouter Responses currently drops extraBody; Chat Completions sends it.
    model["api"] = "openai-completions"
    matches = plugins.select { |plugin| plugin.is_a?(Hash) && plugin["id"] == "auto-router" }
    raise "#{path}: duplicate auto-router plugins" if matches.length > 1
    plugin = matches.first || {"id" => "auto-router"}.tap { |entry| plugins << entry }
    plugin["allowed_models"] = pool
    body["plugins"] = plugins
    # Every candidate accepts this window and output limit, regardless of provider.
    model["contextWindow"] = 1_000_000
    model["maxTokens"] = 32_768
    if Marshal.dump(data) == before
      puts "Auto Code model pool already set — left as-is."
      next
    end

    serialized = YAML.dump(data).delete_prefix("---\n")
    mode = File.exist?(path) ? File.stat(path).mode & 0o777 : 0o600
    tmp = "#{path}.tmp.#{$$}"
    begin
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(serialized)
        file.flush
        file.fsync
      end
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
    puts "Configured Auto Code model pool in #{path}"
  end
' "$config_dir"
