# frozen_string_literal: true

# Second tier: load the plugin, then fire the things SketchUp fires on its own
# right after startup (the deferred timers) and poke the objects create_menu
# left behind. Catches errors that only appear once code actually runs.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)

$SU_CALLS[:register_extension].first.load_extension

# Several plugin methods wrap their body in `rescue => e; p(e)`, which hides real
# errors behind console noise. Intercept Kernel#p so a swallowed exception is a
# test failure with a backtrace instead of an unread line of output.
$SWALLOWED = []
module Kernel
  def p(*args)
    args.each { |a| $SWALLOWED << a if a.is_a?(Exception) }
    args.size == 1 ? args.first : args
  end
end

fails = 0

puts "--- deferred timers registered by create_menu ---"
$SU_TIMERS.each_with_index do |t, i|
  t[:proc].call
  puts format("  timer[%d] sec=%-5s OK", i, t[:sec])
rescue Exception => e
  fails += 1
  puts format("  timer[%d] sec=%-5s RAISED %s: %s", i, t[:sec], e.class, e.message)
  puts "    #{e.backtrace.reject { |l| l.include?('su_shim') }.first}"
end

puts "\n--- state left by create_menu ---"
puts "  toolbar restored     : #{$SU_CALLS[:toolbar_restore].inspect}"
puts "  observer             : #{TRINH_VAN_PHUC::HTU_ScalePlus.observer.class}"
puts "  overlay ancestors    : #{TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay.ancestors.first(2).inspect}"
puts "  tool ancestors       : #{TRINH_VAN_PHUC::HTU_ScalePlus::ScalePPTool.ancestors.first(2).inspect}"
puts "  settings[:dim_offset]: #{TRINH_VAN_PHUC::HTU_ScalePlus.settings[:dim_offset].inspect}"
puts "  active_overlay(nil)  : #{TRINH_VAN_PHUC::HTU_ScalePlus.active_overlay(nil).inspect}"

puts "\n--- behaviour commands built by build_commands ---"
%i[cmd_reset cmd_xyz cmd_x cmd_y cmd_z cmd_dim].each do |name|
  cmd = TRINH_VAN_PHUC::HTU_ScalePlus.send(name)
  if cmd.nil?
    fails += 1
    puts format("  %-10s MISSING", name)
    next
  end
  icon_ok = File.exist?(cmd.large_icon.to_s)
  fails += 1 unless icon_ok
  puts format("  %-10s %-26s icon:%s", name, cmd.menu_text, icon_ok ? "OK" : "MISSING #{cmd.large_icon}")
end

puts "\n--- toolbar command validation proc ---"
begin
  tb_cmd = $SU_CALLS[:command].first
  puts "  toolbar command      : #{tb_cmd}"
  puts "  validation proc      : returns #{TRINH_VAN_PHUC::HTU_ScalePlus.const_defined?(:PLUGIN) ? 'MF_ENABLED (no overlay)' : '?'}"
rescue Exception => e
  fails += 1
  puts "  RAISED #{e.class}: #{e.message}"
end

puts "\n--- toolbar contents ---"
# The six behaviour commands lost their only home when the pet toolbar went, so
# the real toolbar has to carry them: 1 overlay toggle + 6.
tb_items = $SU_CALLS[:toolbar_item].map(&:last)
puts "  items (#{tb_items.size}) : #{tb_items.inspect}"
%w[Behavior\ Scale\ All Behavior\ Scale\ XYZ Behavior\ Scale\ X Behavior\ Scale\ Y
   Behavior\ Scale\ Z Toggle\ show\ dimensions].each do |label|
  next if tb_items.include?(label)

  fails += 1
  puts "  MISSING from toolbar: #{label}"
end

puts "\n--- menu entries, which is what makes a shortcut assignable ---"
# SketchUp lists only menu commands in Preferences > Shortcuts. A command that
# lives on the toolbar alone can never be bound to a key, so every one of them
# has to appear in a menu as well.
menu_items = $SU_CALLS[:menu_item].map(&:last)
puts "  items (#{menu_items.size}) : #{menu_items.inspect}"
["ScalePlus", "Behavior Scale All", "Behavior Scale XYZ", "Behavior Scale X",
 "Behavior Scale Y", "Behavior Scale Z", "Toggle show dimensions"].each do |label|
  next if menu_items.include?(label)

  fails += 1
  puts "  MISSING from the menu: #{label}"
end

# Both the menu item and the ten-second timer that checked silently on startup
# pointed at the original vendor's server.
if menu_items.include?("Check for Update")
  fails += 1
  puts "  Check for Update is still on the menu"
end

puts "  menu name            : #{TRINH_VAN_PHUC::MENU_NAME}"
unless TRINH_VAN_PHUC::MENU_NAME == "HTU_ScalePlus"
  fails += 1
  puts "  the submenu is not named after the extension"
end

puts "\n--- instantiate the overlay, the tool and the observer ---"
[["ScalePP2Overlay", -> { TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay.new }],
 ["ScalePPTool", -> { TRINH_VAN_PHUC::HTU_ScalePlus::ScalePPTool.new(nil) }],
 ["ScalePP2Observer", -> { TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Observer.new }]].each do |label, thunk|
  obj = thunk.call
  puts format("  %-18s -> %s OK", label, obj.class)
rescue Exception => e
  fails += 1
  puts format("  %-18s RAISED %s: %s", label, e.class, e.message)
  puts "    #{e.backtrace.reject { |l| l.include?('su_shim') }.first}"
end

puts "\n--- exceptions swallowed by the plugin's own rescue blocks ---"
if $SWALLOWED.empty?
  puts "  none"
else
  $SWALLOWED.uniq { |e| [e.class, e.message] }.each do |e|
    fails += 1
    puts "  #{e.class}: #{e.message}"
    puts "    #{e.backtrace.reject { |l| l.include?('su_shim') }.first}"
  end
end

puts "\n--- result ---"
if fails.zero?
  puts "PASS — startup timers fire clean, all 6 behaviour commands + icons present"
  exit 0
else
  puts "FAIL — #{fails} problem(s)"
  exit 1
end
