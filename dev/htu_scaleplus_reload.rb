# encoding: UTF-8
#
# htu_scaleplus_reload.rb
#
# Reloads HTU ScalePlus in place so SketchUp does not have to restart, and does
# not have to reinstall the .rbz either.
#
#   load "E:/htu_scaleplus/dev/htu_scaleplus_reload.rb"
#   HTU_ScalePlusReload.run
#
# Dropped in the Plugins folder it defines itself at startup, so from then on
# only the second line is needed. Same shape as htu_drawers_reload.rb.
#
# What it takes care of, in order:
#   - copies the edited files from the repo over the INSTALLED copy, because
#     that is the one SketchUp is running; reloading the repo copy while the
#     installed one is live is the classic way to chase an already-fixed bug
#   - drops the tool, since a pushed tool holds a half-replaced class
#   - loads the sub-files in the SAME order loader.rb requires them.
#     Sketchup.require would skip them: they are already in $LOADED_FEATURES,
#     which is exactly why editing a sub-file looks like "nothing changed"
#   - rebuilds the overlay's ScalePPTool. Redefined methods reach the existing
#     instance, but a changed `initialize` does not
#   - prints each file's MD5, so a stale copy is obvious
module HTU_ScalePlusReload

  # Same order as the require list in loader.rb. loader.rb comes last: it is
  # safe to reload (create_menu sits behind file_loaded?, so the toolbar and
  # menus are not stacked a second time) and it carries the settings defaults.
  SUB_FILES = %w[
    utils main group_lock tool dim_favorites dim_menu dim_add_dialog scale_tool
    dims observer overlay loader
  ].freeze

  # The repo being edited. Set to nil to reload in place without syncing.
  SOURCE_ROOT = "E:/htu_scaleplus/htu_scaleplus".freeze

  # Where the RUNNING copy lives, found through a file the plugin actually
  # loaded rather than through a guessed Plugins path.
  def self.loaded_root
    hit = $LOADED_FEATURES.reverse.find do |path|
      File.basename(path) == "loader.rb" && path.include?("htu_scaleplus")
    end
    return File.dirname(hit) if hit && File.exist?(hit)
    File.dirname(__FILE__)
  end

  def self.md5(path)
    require "digest/md5"
    Digest::MD5.file(path).hexdigest[0, 8].upcase
  rescue StandardError
    "????????"
  end

  # Copies only the known file list, never deletes. A file that is already
  # identical is skipped so the printed count means something.
  def self.sync(root)
    return 0 if SOURCE_ROOT.nil? || !File.directory?(SOURCE_ROOT)
    return 0 if File.expand_path(SOURCE_ROOT).casecmp(File.expand_path(root)).zero?

    require "fileutils"
    copied = 0
    SUB_FILES.each do |name|
      src = File.join(SOURCE_ROOT, "#{name}.rb")
      dst = File.join(root, "#{name}.rb")
      next unless File.exist?(src)
      next if File.exist?(dst) && md5(src) == md5(dst)

      FileUtils.cp(src, dst)
      copied += 1
    end
    copied
  end

  def self.run
    model = Sketchup.active_model
    root = loaded_root

    copied = begin
      sync(root)
    rescue StandardError => e
      puts "HTU reload: sync loi (#{e.message}) - reload copy dang chay."
      0
    end

    files = SUB_FILES.map { |name| File.join(root, "#{name}.rb") }
    missing = files.reject { |path| File.exist?(path) }
    unless missing.empty?
      puts "HTU reload: thieu file:"
      missing.each { |path| puts "  #{path}" }
      return false
    end

    # A tool left on the stack keeps drawing through the class being replaced.
    begin
      model.select_tool(nil)
    rescue StandardError
      nil
    end

    verbose = $VERBOSE
    $VERBOSE = nil # reloading constants is expected here
    loaded = []
    begin
      files.each do |path|
        load path
        loaded << path
      end
    rescue StandardError, ScriptError => e
      puts "HTU reload FAILED tai #{loaded.length + 1}/#{files.length}: #{files[loaded.length]}"
      puts "  #{e.class}: #{e.message}"
      Array(e.backtrace)[0, 5].each { |line| puts "  #{line}" }
      return false
    ensure
      $VERBOSE = verbose
    end

    rebuilt = restart_overlays(model)

    puts "== HTU ScalePlus reloaded =="
    puts "root: #{root}"
    puts "sync: #{copied} file(s) tu #{SOURCE_ROOT}" if copied.positive?
    files.each { |path| puts "  #{md5(path)}  #{File.basename(path)}" }
    puts "overlay: #{rebuilt} rebuilt"
    true
  end

  # Overlay#start throws away @tools and builds a fresh ScalePPTool, which is
  # what picks up a changed initialize. Enabling again matters because a reload
  # that leaves the overlay off looks exactly like a reload that did nothing.
  def self.restart_overlays(model)
    klass = TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay
    count = 0
    model.overlays.each do |overlay|
      next unless overlay.is_a?(klass) && overlay.valid?

      # Enable before start, not after: Overlay#start ends in tool_changed,
      # which returns early while the overlay is still disabled, and the tool
      # would then sit inactive until the next tool switch.
      overlay.enabled = true
      overlay.start
      count += 1
    end
    model.active_view.invalidate
    count
  rescue StandardError => e
    puts "HTU reload: overlay khong rebuild duoc (#{e.message})"
    0
  end

end

# No menu entry on purpose: this is a dev file, and the Extensions menu should
# carry only what ships. Nothing is reloaded on load either - sitting in the
# Plugins folder it runs during boot, where reloading would hit a half
# initialised state.
puts "HTU ScalePlus Reload: go HTU_ScalePlusReload.run trong Ruby Console"
