#!/bin/bash
# Suffix anthropic/* model names with " (sub)" so the Claude-subscription
# models stand apart from their identically named openrouter/* twins in
# pickers that show only the name (Zed's ACP model selector).
set -euo pipefail

config_dir="$(omp config path)"
mkdir -p "$config_dir"

# Same legacy-JSON migration guard as setup-auto-code.sh.
if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" && -e "$config_dir/models.json" ]]; then
  omp models find anthropic --json >/dev/null
  if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" ]]; then
    echo "Error: OMP did not migrate $config_dir/models.json; label setup stopped." >&2
    exit 1
  fi
fi

omp models anthropic --json | ruby -rjson -ryaml -e '
  suffix = " (sub)"
  dir = ARGV.fetch(0)
  yml = File.join(dir, "models.yml")
  yaml = File.join(dir, "models.yaml")
  path = File.exist?(yml) || !File.exist?(yaml) ? yml : yaml
  raise "#{path}: refusing to replace a symlink" if File.symlink?(path)
  models = JSON.parse($stdin.read).fetch("models").select { |m| m["provider"] == "anthropic" }
  raise "no anthropic models listed; is omp logged in?" if models.empty?

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
    overrides = mapping(mapping(mapping(data, "providers", path), "anthropic", path), "modelOverrides", path)
    models.each do |m|
      model = mapping(overrides, m.fetch("id"), path)
      # A name set by hand (without the suffix) wins.
      next if model["name"] && !model["name"].end_with?(suffix)
      model["name"] = m.fetch("name").delete_suffix(suffix) + suffix
    end
    if Marshal.dump(data) == before
      puts "Subscription model labels already set — left as-is."
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
    puts "Labelled #{models.length} anthropic models in #{path}"
  end
' "$config_dir"
