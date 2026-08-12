# frozen_string_literal: true

# Package the plaintext source tree into an installable .rbz.
#
#   ruby build.rb
#
# An .rbz IS a zip — SketchUp's Extension Manager just wants the extension
# registration file at the archive ROOT (not inside a wrapper folder), next to
# the same-named support folder. That layout is what gets written here.
#
# Runs the verification suite first and refuses to package if anything fails.

require "fileutils"
require "rbconfig"

# Subshells on Windows spawn cmd.exe, which does not inherit a POSIX-style PATH,
# so bare `ruby` is often not resolvable. Always call the running interpreter.
RUBY = RbConfig.ruby

begin
  require "zip"
  HAVE_RUBYZIP = true
rescue LoadError
  HAVE_RUBYZIP = false
end

ROOT     = __dir__
DIST     = File.join(ROOT, "dist")
VERSION  = File.read(File.join(ROOT, "htu_scaleplus.rb"))[/PLUGIN_VERSION\s*=\s*'([^']+)'/, 1]
RBZ_NAME = "htu_scaleplus-#{VERSION}.rbz"
RBZ      = File.join(DIST, RBZ_NAME)

# Everything that ships. test/, dist/, dev/, build.rb and docs stay out of the
# archive.
EXCLUDE_DIRS  = %w[test dist docs dev .git].freeze
EXCLUDE_FILES = %w[build.rb README_BUILD.md].freeze
# *.susig is Trimble's extension signature, which hashes every shipped file.
# This build replaces loader.rb and edits six others, so the original signature
# can no longer validate — and a signature that fails is worse than none, since
# SketchUp reports it as tampered. Ship unsigned instead.
EXCLUDE_GLOBS = %w[.DS_Store Thumbs.db *.orig *.rej *.susig].freeze

def payload_files
  Dir.glob(File.join(ROOT, "**", "*"), File::FNM_DOTMATCH)
     .reject { |p| File.directory?(p) }
     .map    { |p| p.sub(ROOT + File::SEPARATOR, "").tr("\\", "/") }
     .reject { |r| r.start_with?(".") && !r.include?("/") }
     .reject { |r| EXCLUDE_DIRS.any? { |d| r == d || r.start_with?("#{d}/") } }
     .reject { |r| EXCLUDE_FILES.include?(r) }
     .reject { |r| EXCLUDE_GLOBS.any? { |g| File.fnmatch(g, File.basename(r)) } }
     .sort
end

# ------------------------------------------------------------------- verify
puts "== verify =="

syntax_fails = Dir.glob(File.join(ROOT, "**", "*.rb")).reject do |f|
  `"#{RUBY}" -c "#{f}" 2>&1`.strip == "Syntax OK"
end
unless syntax_fails.empty?
  abort "ABORT: ruby -c failed for:\n  #{syntax_fails.join("\n  ")}"
end
puts "  ruby -c            : OK (#{Dir.glob(File.join(ROOT, '**', '*.rb')).size} files)"

{
  "dropped-param scan" => "test/dropped_param_scan.rb",
  "load test"          => "test/load_test.rb",
  "runtime test"       => "test/runtime_test.rb",
  "dim favorites test" => "test/dim_favorites_test.rb",
  "dim menu test"      => "test/dim_menu_test.rb",
  "dim edit test"      => "test/dim_edit_test.rb",
  "add dialog test"    => "test/dim_add_dialog_test.rb",
  "retarget test"      => "test/retarget_test.rb",
  "behavior test"      => "test/behavior_test.rb",
  "group lock test"    => "test/group_lock_test.rb",
  "navigation test"    => "test/navigation_test.rb",
  "text size test"     => "test/text_size_persistence_test.rb",
}.each do |label, script|
  out = `"#{RUBY}" "#{File.join(ROOT, script)}" 2>&1`
  abort "ABORT: #{label} failed\n#{out}" unless $?.success?
  puts format("  %-18s : PASS", label)
end

# The registration file must sit at the archive root for SketchUp to find it.
abort "ABORT: htu_scaleplus.rb missing" unless File.exist?(File.join(ROOT, "htu_scaleplus.rb"))

files = payload_files
abort "ABORT: no payload files found" if files.empty?
unless files.include?("htu_scaleplus.rb")
  abort "ABORT: htu_scaleplus.rb would not be in the archive root"
end

# ------------------------------------------------------------------ package
puts "\n== package =="
FileUtils.mkdir_p(DIST)
File.delete(RBZ) if File.exist?(RBZ)

if HAVE_RUBYZIP
  Zip::File.open(RBZ, Zip::File::CREATE) do |zip|
    files.each { |rel| zip.add(rel, File.join(ROOT, rel)) }
  end
else
  # No rubygems dependency: shell out to PowerShell's Compress-Archive via a
  # staging folder, then rename .zip -> .rbz.
  stage = File.join(DIST, "stage")
  FileUtils.rm_rf(stage)
  files.each do |rel|
    dest = File.join(stage, rel)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(File.join(ROOT, rel), dest)
  end
  zip = File.join(DIST, "#{File.basename(RBZ_NAME, '.rbz')}.zip")
  File.delete(zip) if File.exist?(zip)
  ps = %(Compress-Archive -Path "#{stage}\\*" -DestinationPath "#{zip}" -Force)
  abort "ABORT: Compress-Archive failed" unless system("powershell", "-NoProfile", "-Command", ps)
  FileUtils.mv(zip, RBZ)
  FileUtils.rm_rf(stage)
end

puts "  #{files.size} files -> #{RBZ}"
puts "  size: #{(File.size(RBZ) / 1024.0).round(1)} KB"

# ------------------------------------------------------------------- report
puts "\n== archive contents (top level) =="
files.group_by { |r| r.include?("/") ? r.split("/")[0, 2].join("/") : "(root)" }
     .sort
     .each { |group, fs| puts format("  %-38s %d file(s)", group, fs.size) }

puts "\nDone. Install with Extension Manager -> Install Extension -> #{RBZ_NAME}"
