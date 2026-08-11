# frozen_string_literal: true

# Load HTU ScalePlus end to end under the shim and report what got wired up.
# Exits non-zero on any load-time error.

require_relative "su_shim"

ROOT = File.expand_path("..", __dir__)

def section(title)
  puts "\n--- #{title} ---"
end

begin
  require File.join(ROOT, "htu_scaleplus.rb")
rescue Exception => e
  warn "FAIL registering extension: #{e.class}: #{e.message}"
  warn e.backtrace.first(12).join("\n")
  exit 1
end

ex = $SU_CALLS[:register_extension].first
unless ex
  warn "FAIL: no extension registered"
  exit 1
end

section "extension"
puts "name        : #{ex.name}"
puts "version     : #{ex.version}"
puts "creator     : #{ex.creator}"
puts "copyright   : #{ex.copyright}"
puts "loader path : #{ex.path}"

begin
  ex.load_extension
rescue Exception => e
  warn "FAIL loading plugin: #{e.class}: #{e.message}"
  warn e.backtrace.reject { |l| l.include?("su_shim") }.first(15).join("\n")
  exit 1
end

section "loaded ruby files"
loaded = $LOADED_FEATURES.select { |f| f.include?("htu_scaleplus") }
loaded.each { |f| puts "  #{f.sub(ROOT.tr('\\', '/') + '/', '')}" }
puts "count: #{loaded.size}"

section "constants under TRINH_VAN_PHUC::HTU_ScalePlus"
mods = TRINH_VAN_PHUC::HTU_ScalePlus.constants.sort
puts mods.join(", ")

section "UI wired up"
puts "commands   : #{$SU_CALLS[:command].inspect}"
puts "toolbars   : #{$SU_CALLS[:toolbar].inspect}"
puts "menu items : #{$SU_CALLS[:menu_item].inspect}"
puts "timers     : #{$SU_TIMERS.map { |t| t[:sec] }.inspect}"
puts "messagebox : #{$SU_CALLS[:messagebox].inspect}"

section "key entry points respond?"
checks = {
  "PLUGIN.toggle"            => TRINH_VAN_PHUC::HTU_ScalePlus.respond_to?(:toggle),
  "PLUGIN.build_commands"    => TRINH_VAN_PHUC::HTU_ScalePlus.respond_to?(:build_commands),
  "PLUGIN.set_behavior"      => TRINH_VAN_PHUC::HTU_ScalePlus.respond_to?(:set_behavior),
  "PLUGIN.active_overlay"    => TRINH_VAN_PHUC::HTU_ScalePlus.respond_to?(:active_overlay),
  "PLUGIN.create_menu"       => TRINH_VAN_PHUC::HTU_ScalePlus.respond_to?(:create_menu),
  "PLUGIN.observer set"      => !TRINH_VAN_PHUC::HTU_ScalePlus.observer.nil?,
  "PLUGIN.settings set"      => !TRINH_VAN_PHUC::HTU_ScalePlus.settings.nil?,
  "ScalePP2Overlay defined"  => TRINH_VAN_PHUC::HTU_ScalePlus.const_defined?(:ScalePP2Overlay),
  "ScalePPTool defined"      => TRINH_VAN_PHUC::HTU_ScalePlus.const_defined?(:ScalePPTool),
  "DimsUI.show_dialog"       => TRINH_VAN_PHUC::HTU_ScalePlus::DimsUI.respond_to?(:show_dialog),
  "Update.check"             => TRINH_VAN_PHUC::HTU_ScalePlus::Update.respond_to?(:check),
  "RadialMenu module"        => TRINH_VAN_PHUC::HTU_ScalePlus.const_defined?(:RadialMenu),
}

fails = 0
checks.each do |label, ok|
  puts format("  %-28s %s", label, ok ? "OK" : "MISSING")
  fails += 1 unless ok
end

section "resource files referenced by the loaded code"
res = [
  "htu_scaleplus/Resources/icon.svg",
  "htu_scaleplus/Resources/icon.pdf",
  "htu_scaleplus/Resources/reset.png",
  "htu_scaleplus/Resources/icon_xyz.png",
  "htu_scaleplus/Resources/icon_x.png",
  "htu_scaleplus/Resources/icon_y.png",
  "htu_scaleplus/Resources/icon_z.png",
  "htu_scaleplus/Resources/show_dim.png",
  "htu_scaleplus/radial_menu/Resources/missing.png",
  "htu_scaleplus/radial_menu/Resources/text_command.png",
  "htu_scaleplus/radial_menu/Resources/tb_unknown.png",
  "htu_scaleplus/ui/html/dims.html",
  "htu_scaleplus/ui/js/dims.js",
  "htu_scaleplus/ui/css/dims.css",
  "htu_scaleplus/SF Pro Rounded_Bold.json",
]
res.each do |r|
  ok = File.exist?(File.join(ROOT, r))
  puts format("  %-52s %s", r, ok ? "OK" : "MISSING")
  fails += 1 unless ok
end

section "result"
if fails.zero?
  puts "PASS — plugin loads clean, all entry points and resources present"
  exit 0
else
  puts "FAIL — #{fails} problem(s)"
  exit 1
end
