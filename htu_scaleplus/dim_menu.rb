module TRINH_VAN_PHUC::HTU_ScalePlus
  # Builds the context menu shown when right-clicking a dimension:
  #
  #   45 mm            <- the saved sizes, checked when one is the current length
  #   200 mm
  #   400 mm
  #   ---------
  #   Open list...     add, delete, delete all -- all in one window
  #   Text size  >     Small / Medium / Large
  #
  # One list serves all three axes, but picking a size still applies it to the
  # axis of the dimension that was right-clicked -- which is why the axis is
  # threaded through here.
  #
  # There used to be Add... and a Del submenu as well. Both are gone: the window
  # does each job better, because a native menu closes on the first pick and so
  # every added or deleted value cost a fresh trip through the menu.
  module DimMenu
    def self.build(menu, tool, object, axis, length)
      values = DimFavorites.list(object, axis)

      if object
        add_value_items(menu, tool, axis, length, values)
        unless values.empty?
          menu.add_separator
        end
        menu.add_item("Open list...") { defer { DimAddDialog.show(object, axis) } }
      end

      add_text_size_submenu(menu)
    end

    # A saved size applies immediately -- one click, no confirmation.
    def self.add_value_items(menu, tool, axis, length, values)
      values.each do |value|
        item = menu.add_item(value.to_s) { tool.apply_dim_value(axis, value) }
        menu.set_validation_proc(item) do
          value == length ? MF_CHECKED : MF_ENABLED
        end
      end
    end

    def self.add_text_size_submenu(menu)
      submenu = menu.add_submenu("Text size")
      { "Small" => DIM_SMALL, "Medium" => DIM_MEDIUM, "Large" => DIM_LARGE }.each do |label, size|
        item = submenu.add_item(label) do
          PLUGIN.settings[:dim_text_size] = size
          Sketchup.active_model.active_view.invalidate
        end
        submenu.set_validation_proc(item) do
          PLUGIN.settings[:dim_text_size] == size ? MF_CHECKED : MF_ENABLED
        end
      end
    end

    # On Windows a modal dialog opened straight from a menu callback can land
    # behind the SketchUp window; the existing code defers it by a tick to avoid
    # that, and the same workaround applies here.
    def self.defer(&block)
      unless IS_WIN
        return block.call
      end
      id = UI.start_timer(0.1, false) do
        UI.stop_timer(id)
        block.call
      end
    end
  end
end
