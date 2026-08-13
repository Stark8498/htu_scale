module TRINH_VAN_PHUC::HTU_ScalePlus
  # Builds the context menu shown when right-clicking a dimension:
  #
  #   45 mm                 <- the saved sizes, checked when one is the current length
  #   200 mm
  #   ---------
  #   Referenced Dimensions <- grayed heading, only when there are any
  #   900 mm (in model)     <- sizes this component is already built at elsewhere
  #   ---------
  #   Open list...          add, delete, delete all -- all in one window
  #   Text size  >          Small / Medium / Large
  #
  # With nothing saved and nothing referenced, that is the whole menu: Open list...
  # and Text size, no divider above them.
  #
  # One list serves all three axes, but picking a size still applies it to the
  # axis of the dimension that was right-clicked -- which is why the axis is
  # threaded through here.
  #
  # There used to be Add... and a Del submenu as well. Both are gone: the window
  # does each job better, because a native menu closes on the first pick and so
  # every added or deleted value cost a fresh trip through the menu.
  #
  # Three of the original's items are gone by request, not by accident:
  #
  #   "Favorite Dimensions" -- a grayed heading over the first block. The block is
  #   the top of the menu and the sizes are what the menu is for, so the label was
  #   an unclickable row explaining the obvious. "Referenced Dimensions" stays,
  #   because it is what tells the second block apart from the first.
  #
  #   "Show Manager" -- opened the old Vue dimension dialog. "Open list..." above
  #   it does the same job in a window built for it. Nothing else opens DimsUI now,
  #   so that dialog is unreachable while it still ships; observer.rb's calls into
  #   it are no-ops with no dialog to refresh.
  #
  #   The half and double suggestions -- "225 (x0.5)" and "900 (x2.0)", shown only
  #   while nothing was saved. They were a multiplication offered as a size, which
  #   is what dragging a grip already does. The cost is real and was weighed: this
  #   was the ONLY thing the menu offered on a fresh install, so a first right-click
  #   now has no size on it until one is saved through Open list...
  #
  # Everything else here is Curic Scale++ 1.1.2's own menu, including Referenced
  # Dimensions, which was dropped while this file was being written and is back.
  module DimMenu
    def self.build(menu, tool, object, axis, length)
      values = DimFavorites.list(object, axis)

      if object
        add_value_items(menu, tool, axis, length, values)
        listed = !values.empty?
        if add_referenced_items(menu, tool, axis, length, values, listed)
          listed = true
        end
        # A separator divides, so it needs a block on both sides. Since the
        # suggestions went there is nothing above it on a fresh install, and a menu
        # that opens with a horizontal rule reads as an item that failed to draw.
        if listed
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

    # Sizes the same component is already built at elsewhere in the model. Minus
    # the saved ones, which are listed above, and minus the current length, which
    # would be a no-op.
    #
    # Returns whether it put anything on the menu, so the caller knows whether
    # there is a block for the separator below to divide. `divide` is the same
    # question asked of what came before this block.
    def self.add_referenced_items(menu, tool, axis, length, values, divide = true)
      unless tool.respond_to?(:referenced_dims)
        return false
      end
      lengths = tool.referenced_dims(axis).to_a - values.to_a
      lengths = lengths.reject { |value| value == length }
      if lengths.empty?
        return false
      end
      if divide
        menu.add_separator
      end
      add_heading(menu, "Referenced Dimensions")
      lengths.each do |value|
        menu.add_item("#{value} (in model)") { tool.apply_dim_value(axis, value) }
      end
      true
    end

    # A grayed item standing in for a group label, which is how the original
    # separated the blocks. Only the referenced one uses it now: it comes after a
    # list of saved sizes that looks exactly like it, so something has to say
    # where one ends and the other starts.
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
