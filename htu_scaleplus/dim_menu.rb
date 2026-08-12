module TRINH_VAN_PHUC::HTU_ScalePlus
  # Builds the context menu shown when right-clicking a dimension:
  #
  #   Favorite Dimensions   <- grayed heading, only above saved sizes
  #   45 mm                 <- the saved sizes, checked when one is the current length
  #   200 mm
  #   ---------
  #   Referenced Dimensions <- grayed heading, only when there are any
  #   900 mm (in model)     <- sizes this component is already built at elsewhere
  #   ---------
  #   Open list...          add, delete, delete all -- all in one window
  #   Show Manager          the older Vue dimension manager
  #   Text size  >          Small / Medium / Large
  #
  # With nothing saved yet, the saved block is replaced by two suggestions:
  #
  #   225 mm (x0.5)
  #   900 mm (x2.0)
  #
  # One list serves all three axes, but picking a size still applies it to the
  # axis of the dimension that was right-clicked -- which is why the axis is
  # threaded through here.
  #
  # There used to be Add... and a Del submenu as well. Both are gone: the window
  # does each job better, because a native menu closes on the first pick and so
  # every added or deleted value cost a fresh trip through the menu.
  #
  # Everything else here is Curic Scale++ 1.1.2's own menu. The half/double
  # suggestions, both headings, Referenced Dimensions and Show Manager were
  # dropped while this file was being written and are back: on a fresh install the
  # suggestions were the ONLY thing the menu offered, and Show Manager was the
  # only way to open the Vue manager, which still ships.
  module DimMenu
    def self.build(menu, tool, object, axis, length)
      values = DimFavorites.list(object, axis)

      if object
        if values.empty?
          add_suggested_items(menu, tool, axis, length)
        else
          add_heading(menu, "Favorite Dimensions")
          add_value_items(menu, tool, axis, length, values)
        end
        add_referenced_items(menu, tool, axis, length, values)
        menu.add_separator
        menu.add_item("Open list...") { defer { DimAddDialog.show(object, axis) } }
        menu.add_item("Show Manager") { DimsUI.show_dialog }
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

    # Half and double, labelled with the factor. This is the entire menu on a
    # fresh install, which is why losing it was worse than it looks: right-click
    # offered nothing to click.
    SUGGESTED_FACTORS = [0.5, 2].freeze

    def self.add_suggested_items(menu, tool, axis, length)
      unless length && length.to_f > 0
        return
      end
      SUGGESTED_FACTORS.each do |factor|
        value = (length * factor).to_l
        label = "#{value} (x#{(value / length).round(1)})"
        menu.add_item(label) { tool.apply_dim_value(axis, value) }
      end
    end

    # Sizes the same component is already built at elsewhere in the model. Minus
    # the saved ones, which are listed above, and minus the current length, which
    # would be a no-op.
    def self.add_referenced_items(menu, tool, axis, length, values)
      unless tool.respond_to?(:referenced_dims)
        return
      end
      lengths = tool.referenced_dims(axis).to_a - values.to_a
      lengths = lengths.reject { |value| value == length }
      if lengths.empty?
        return
      end
      menu.add_separator
      add_heading(menu, "Referenced Dimensions")
      lengths.each do |value|
        menu.add_item("#{value} (in model)") { tool.apply_dim_value(axis, value) }
      end
    end

    # A grayed item standing in for a group label, which is how the original
    # separated the two blocks. Both are lists of bare lengths, so without the
    # labels there is nothing to say which is which.
    def self.add_heading(menu, text)
      item = menu.add_item(text) {}
      menu.set_validation_proc(item) { MF_GRAYED }
      item
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
