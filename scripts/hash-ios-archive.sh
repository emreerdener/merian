#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: Could not identify iOS archive: $*" >&2
  exit 1
}

(( $# == 1 )) || fail "usage: $0 ARCHIVE_PATH"

archive_path="$1"
[[ -d "$archive_path" && ! -L "$archive_path" ]] \
  || fail "archive must be a non-symbolic-link directory: $archive_path"
command -v ruby >/dev/null 2>&1 || fail "ruby is unavailable."

ruby -rdigest -rfind -e '
  root = File.realpath(ARGV.fetch(0))
  records = []

  Find.find(root) do |path|
    next if path == root

    relative = path.delete_prefix(root + File::SEPARATOR)
    abort("archive path contains unsupported control characters") if relative.match?(/[\t\r\n]/)
    metadata = File.lstat(path)
    mode = metadata.mode & 0o7777

    record = case metadata.ftype
             when "directory"
               ["directory", mode.to_s(8), relative]
             when "file"
               before = [metadata.size, metadata.mtime.to_f]
               digest = Digest::SHA256.file(path).hexdigest
               after_metadata = File.lstat(path)
               after = [after_metadata.size, after_metadata.mtime.to_f]
               abort("archive file changed while hashing: #{relative}") unless before == after
               ["file", mode.to_s(8), metadata.size.to_s, digest, relative]
             when "link"
               ["link", mode.to_s(8), File.readlink(path), relative]
             else
               abort("archive contains unsupported #{metadata.ftype}: #{relative}")
             end

    records << record.map { |value| "#{value.bytesize}:#{value}" }.join("|")
  end

  abort("archive is empty") if records.empty?
  puts Digest::SHA256.hexdigest(records.sort.join("\n") + "\n")
' "$archive_path"
