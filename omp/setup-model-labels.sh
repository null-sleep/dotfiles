#!/bin/bash
# Suffix subscription-provider model names with " (sub)" so the Claude
# (anthropic) and ChatGPT (openai-codex) subscription models stand apart from
# their identically named openrouter/* twins in pickers that show only the
# name (Zed's ACP model selector).
set -euo pipefail

config_dir="$(omp config path)"
mkdir -p "$config_dir"

# Let OMP migrate legacy JSON before creating an override YAML of our own.
if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" && -e "$config_dir/models.json" ]]; then
  omp models find anthropic --json >/dev/null
  if [[ ! -e "$config_dir/models.yml" && ! -e "$config_dir/models.yaml" ]]; then
    echo "Error: OMP did not migrate $config_dir/models.json; label setup stopped." >&2
    exit 1
  fi
fi

providers=(anthropic openai-codex)
ruby -rjson -ryaml -ropen3 -e '
  suffix = " (sub)"
  dir = ARGV.fetch(0)
  wanted = ARGV.drop(1)
  yml = File.join(dir, "models.yml")
  yaml = File.join(dir, "models.yaml")
  path = File.exist?(yml) || !File.exist?(yaml) ? yml : yaml
  raise "#{path}: refusing to replace a symlink" if File.symlink?(path)
  models = wanted.flat_map do |provider|
    out, status = Open3.capture2("omp", "models", provider, "--json")
    raise "omp models #{provider} failed" unless status.success?
    JSON.parse(out).fetch("models").select { |m| m["provider"] == provider }
  end
  # The static catalog can omit subscription models OMP discovers only at
  # session start (e.g. openai-codex/gpt-6.1-sol), leaving them unlabelled,
  # so also label each subscription model a role selects, named after its
  # openrouter twin. Role values are a string, comma list, or array; `@alias`
  # entries are skipped (their targets are roles too); `@upstream` pins and
  # `:thinking` suffixes are stripped.
  out, status = Open3.capture2("omp", "config", "get", "modelRoles", "--json")
  raise "omp config get modelRoles failed" unless status.success?
  roles = JSON.parse(out).fetch("value") || {}
  known = models.map { |m| [m["provider"], m["id"]] }
  selectors = roles.values.flat_map { |v| Array(v) }.grep(String)
    .flat_map { |v| v.split(",") }.map(&:strip).reject { |s| s.empty? || s.start_with?("@") }
  selectors.each do |selector|
    provider, id = selector.sub(/:[a-z]+\z/, "").sub(/@.*\z/, "").split("/", 2)
    next unless wanted.include?(provider) && id && !id.empty? && !known.include?([provider, id])
    vendor = provider == "anthropic" ? "anthropic" : "openai"
    twin_id = provider == "anthropic" ? id.gsub(/(\d)-(\d)/, "\\1.\\2") : id
    out, status = Open3.capture2("omp", "models", "find", twin_id, "--json")
    next unless status.success?
    twin = JSON.parse(out).fetch("models").find { |m| m["provider"] == "openrouter" && m["id"] == "#{vendor}/#{twin_id}" }
    next unless twin
    models << { "provider" => provider, "id" => id, "name" => twin.fetch("name") }
    known << [provider, id]
  end
  raise "no subscription models listed; is omp logged in?" if models.empty?

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
    models.each do |m|
      overrides = mapping(mapping(mapping(data, "providers", path), m.fetch("provider"), path), "modelOverrides", path)
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
    counts = models.group_by { |m| m["provider"] }.map { |p, ms| "#{ms.length} #{p}" }.join(", ")
    puts "Labelled #{counts} models in #{path}"
  end
' "$config_dir" "${providers[@]}"
