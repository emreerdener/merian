#!/usr/bin/env bash
set -euo pipefail

repo_root="$(
  if [[ -n "${IOS_SOURCE_MEMBERSHIP_ROOT:-}" ]]; then
    printf '%s\n' "$IOS_SOURCE_MEMBERSHIP_ROOT"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
)"
cd "$repo_root"

if [[ -n "${IOS_SOURCE_MEMBERSHIP_PROJECT:-}" ]]; then
  project_path="$IOS_SOURCE_MEMBERSHIP_PROJECT"
elif [[ -d "Merian.xcodeproj" ]]; then
  project_path="$repo_root/Merian.xcodeproj"
elif [[ -d "merian.xcodeproj" ]]; then
  project_path="$repo_root/merian.xcodeproj"
else
  echo "Missing generated Merian Xcode project." >&2
  exit 1
fi

spec_path="${IOS_SOURCE_MEMBERSHIP_SPEC:-$repo_root/project.yml}"
if [[ ! -f "$spec_path" ]]; then
  echo "Missing XcodeGen source of truth at $spec_path." >&2
  exit 1
fi

ruby - "$repo_root" "$project_path" "$spec_path" <<'RUBY'
require "pathname"
require "set"
require "yaml"

begin
  require "xcodeproj"
rescue LoadError => error
  warn "The xcodeproj Ruby gem is required to validate generated source membership: #{error.message}"
  exit 1
end

repo_root = Pathname.new(ARGV.fetch(0)).realpath
project_path = Pathname.new(ARGV.fetch(1))
spec_path = Pathname.new(ARGV.fetch(2))

begin
  spec = YAML.safe_load(
    File.read(spec_path),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: true
  )
rescue Psych::Exception => error
  warn "Could not safely parse #{spec_path}: #{error.message}"
  exit 1
end

unless spec.is_a?(Hash) && spec["targets"].is_a?(Hash)
  warn "#{spec_path} must define a targets mapping."
  exit 1
end

source_extensions = Set.new(
  %w[.swift .m .mm .c .cc .cpp .cxx .metal .s .S .intentdefinition]
)
supported_source_keys = Set.new(%w[path excludes])

def canonical_file(path)
  Pathname.new(path).realpath.to_s
rescue Errno::ENOENT, Errno::EACCES
  nil
end

def excluded?(relative_path, patterns)
  flags = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB
  patterns.any? do |pattern|
    File.fnmatch?(pattern, relative_path, flags)
  end
end

def display_path(path, repo_root)
  pathname = Pathname.new(path)
  pathname.relative_path_from(repo_root).to_s
rescue ArgumentError
  pathname.to_s
end

project = Xcodeproj::Project.open(project_path.to_s)
project_targets = {}
project.targets.each { |target| project_targets[target.name] = target }
validation_failed = false
all_expected_sources = Set.new

spec["targets"].each do |target_name, target_spec|
  next unless target_spec.is_a?(Hash) && target_spec.key?("sources")

  target = project_targets[target_name]
  unless target
    warn "Generated project is missing target #{target_name.inspect}."
    validation_failed = true
    next
  end

  source_entries = target_spec["sources"]
  unless source_entries.is_a?(Array)
    warn "Target #{target_name.inspect} must define sources as an array."
    validation_failed = true
    next
  end

  expected_sources = Set.new
  entry_failed = false

  source_entries.each do |raw_entry|
    entry =
      case raw_entry
      when String
        { "path" => raw_entry, "excludes" => [] }
      when Hash
        raw_entry
      else
        warn "Target #{target_name.inspect} has an unsupported source entry: #{raw_entry.inspect}"
        entry_failed = true
        next
      end

    unsupported_keys = entry.keys.to_set - supported_source_keys
    unless unsupported_keys.empty?
      warn(
        "Target #{target_name.inspect} source #{entry["path"].inspect} uses " \
        "unsupported membership keys: #{unsupported_keys.to_a.sort.join(", ")}"
      )
      entry_failed = true
      next
    end

    relative_source_path = entry["path"]
    exclude_patterns = entry.fetch("excludes", [])
    unless relative_source_path.is_a?(String) &&
           !relative_source_path.empty? &&
           exclude_patterns.is_a?(Array) &&
           exclude_patterns.all? { |pattern| pattern.is_a?(String) }
      warn "Target #{target_name.inspect} has a malformed source entry: #{entry.inspect}"
      entry_failed = true
      next
    end

    absolute_source_path = repo_root.join(relative_source_path).cleanpath
    unless absolute_source_path.exist?
      warn "Target #{target_name.inspect} source path does not exist: #{relative_source_path}"
      entry_failed = true
      next
    end

    candidates =
      if absolute_source_path.file?
        [absolute_source_path.to_s]
      else
        Dir.glob(
          absolute_source_path.join("**", "*").to_s,
          File::FNM_DOTMATCH
        ).select { |candidate| File.file?(candidate) }
      end

    candidates.each do |candidate|
      next unless source_extensions.include?(File.extname(candidate))

      relative_candidate =
        Pathname.new(candidate).relative_path_from(absolute_source_path).to_s
      next if excluded?(relative_candidate, exclude_patterns)

      canonical_candidate = canonical_file(candidate)
      if canonical_candidate
        expected_sources.add(canonical_candidate)
      else
        warn "Could not resolve source file #{candidate}."
        entry_failed = true
      end
    end
  end

  actual_sources = Set.new
  target.source_build_phase.files_references.compact.each do |file_reference|
    candidate = canonical_file(file_reference.real_path.to_s)
    if candidate
      actual_sources.add(candidate)
    else
      warn(
        "Target #{target_name.inspect} contains an unreadable source reference: " \
        "#{file_reference.real_path}"
      )
      entry_failed = true
    end
  end

  missing_sources = expected_sources - actual_sources
  unexpected_sources = actual_sources - expected_sources
  all_expected_sources.merge(expected_sources)

  unless missing_sources.empty?
    warn "Target #{target_name.inspect} does not compile these project.yml sources:"
    missing_sources.to_a.sort.each do |path|
      warn "  - #{display_path(path, repo_root)}"
    end
    entry_failed = true
  end

  unless unexpected_sources.empty?
    warn "Target #{target_name.inspect} compiles sources absent from project.yml:"
    unexpected_sources.to_a.sort.each do |path|
      warn "  - #{display_path(path, repo_root)}"
    end
    entry_failed = true
  end

  if entry_failed
    validation_failed = true
  else
    puts "Validated #{expected_sources.length} source files for #{target_name}."
  end
end

platform_sources = Set.new
%w[apps/ios apps/watch].each do |relative_platform_root|
  platform_root = repo_root.join(relative_platform_root)
  next unless platform_root.directory?

  Dir.glob(
    platform_root.join("**", "*").to_s,
    File::FNM_DOTMATCH
  ).each do |candidate|
    next unless File.file?(candidate)
    next unless source_extensions.include?(File.extname(candidate))

    canonical_candidate = canonical_file(candidate)
    if canonical_candidate
      platform_sources.add(canonical_candidate)
    else
      warn "Could not resolve platform source file #{candidate}."
      validation_failed = true
    end
  end
end

orphan_sources = platform_sources - all_expected_sources
unless orphan_sources.empty?
  warn "iOS/watch source files outside every project.yml target:"
  orphan_sources.to_a.sort.each do |path|
    warn "  - #{display_path(path, repo_root)}"
  end
  validation_failed = true
end

exit 1 if validation_failed
puts "Generated Xcode project source membership matches project.yml."
RUBY
