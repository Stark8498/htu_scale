# encoding: UTF-8
#
# htu_mask_probe.rb
#
# Vì sao kéo xong thì grip từ 6 nhảy lên 26, trong khi nút trên thanh công cụ vẫn
# đang là XYZ. Trả lời bằng số, không bằng suy luận — cùng lý do với htu_nav_probe.rb.
#
#   load "E:/htu_scaleplus/dev/htu_mask_probe.rb"
#   HTU_MaskProbe.on     # chọn vật, bấm XYZ, rồi KÉO một grip
#   HTU_MaskProbe.off
#
# Chỉ in khi có gì đó ĐỔI, nên console không bị ngập. Làm đúng một lần kéo cho một
# lần chạy rồi chép cả khối ra.
#
# ĐÃ SỬA — main.rb#reassert_behavior, gọi từ observer.rb#scale_finished đúng lúc
# tool_state 1 -> 0. Probe này giờ dùng để XÁC NHẬN trên SketchUp thật, vì cả bộ test
# đều chạy trên shim. Cần thấy: mask tụt về 0 ngay khi buông, rồi một tick sau quay lại
# 120 kèm một lần repick tool. Nếu nó nằm ở 0 và không lên lại thì bản sửa không chạy.
#
# Ba khả năng ban đầu vẫn đáng đọc, vì cột defid nói cái mà bản sửa cố tình không phân
# biệt — đắp lại mask theo `object.definition` đọc mới nên cả ba đều được vá như nhau:
#
#   mask 120 -> 0, defid GIỮ NGUYÊN
#       SketchUp xoá mask trên chính definition ấy khi scale xong.
#
#   mask 120 -> 0, defid ĐỔI
#       Group bị nhân bản definition mới khi transform (definition dùng chung thì
#       make_unique), và definition mới mang behavior mặc định.
#
#   sel 1 -> 2+  (hoặc cls đổi sang Face/Edge)
#       Mask còn nguyên; thứ đổi là SELECTION. Lúc đó compute_bounds_for rơi vào
#       nhánh gộp bbox (no_scale_mask = 0) và axis_locked? trả false — cả hai đều
#       cho 26 grip mà không ai đụng tới mask. Bản sửa gọi GroupLock.wrap cho trường
#       hợp này, nên cột wrap= phải chuyển sang YES sau khi buông.
#
# Các cột:
#
#   sel=     số vật đang chọn. draw_scale_points chỉ đọc mask khi ĐÚNG bằng 1.
#   cls=     lớp của vật đầu tiên. Face/Edge = hình thô, không có definition,
#            và khi ấy axis_locked? trả false mà chẳng liên quan gì tới mask.
#   defid=   object_id của definition. Đổi số nghĩa là definition bị thay, không
#            phải mask bị xoá — hai chuyện khác nhau, sửa khác nhau.
#   mask=    no_scale_mask? thật, đọc ngay lúc đó. 0=all 120=xyz 126=x 125=y 123=z
#   want=    PLUGIN.behavior_state, tức chế độ nút đang sáng. Lệch với mask= là
#            đúng cái bạn nhìn thấy: nút nói XYZ, grip nói all.
#   lock=    axis_locked? — nhánh mà draw_scale_points thật sự chọn.
#   pts=     bb_data[:scale_points].length — số grip plugin sẽ vẽ. 26 / 6 / 2.
#   wrap=    có group tạm của GroupLock không. Chỉ có khi chọn từ 2 vật trở lên.
#   state=   @tool_state. 1 = đang kéo, 0 = đã buông.

module HTU_MaskProbe
  # Gán thẳng sẽ cảnh báo mỗi lần file này được load lại sau một reload.
  P = TRINH_VAN_PHUC::HTU_ScalePlus unless defined?(P)

  class << self
    attr_accessor :last_line, :ticks
  end
  @last_line = nil
  @ticks = 0

  def self.tool
    overlay = P::PLUGIN.active_overlay
    overlay && overlay.dim_scale
  rescue StandardError
    nil
  end

  # Mọi phép đọc đều bọc riêng. Giữa một thao tác scale, bất kỳ cái nào trong số này
  # cũng có thể gặp một entity vừa bị xoá, và một cái probe mà tự nổ thì không đo
  # được đúng khoảnh khắc đáng đo nhất.
  def self.safe
    yield
  rescue StandardError => e
    "!#{e.class}"
  end

  def self.snapshot
    model = Sketchup.active_model
    sel = model.selection.to_a
    first = sel.length == 1 ? sel[0] : nil
    defn = safe { first && first.respond_to?(:definition) ? first.definition : nil }
    t = tool

    format("sel=%-2d cls=%-16s defid=%-12s mask=%-5s want=%-4s lock=%-5s pts=%-4s wrap=%-5s state=%s",
           sel.length,
           safe { sel.empty? ? "-" : sel[0].class.name.split("::").last },
           safe { defn.is_a?(String) ? defn : (defn ? defn.object_id : "-") },
           safe { defn && !defn.is_a?(String) ? defn.behavior.no_scale_mask? : "-" },
           safe { P.behavior_state },
           safe { t ? t.send(:axis_locked?, first) : "-" },
           safe { d = t && t.bb_data; d && d[:scale_points] ? d[:scale_points].length : "-" },
           safe { P::GroupLock.temp_group ? "YES" : "no" },
           safe { t ? t.instance_variable_get(:@tool_state) : "-" })
  end

  def self.on
    off
    @ticks = 0
    @last_line = nil
    @timer = UI.start_timer(0.1, true) do
      begin
        line = snapshot
        # In theo THAY ĐỔI, không theo nhịp đồng hồ. Cái cần thấy là khoảnh khắc
        # chuyển, và một trang toàn dòng giống nhau thì giấu mất nó.
        if line != @last_line
          @ticks += 1
          puts format("%3d  %s", @ticks, line)
          @last_line = line
        end
      rescue StandardError => e
        puts "probe: #{e.class}: #{e.message}"
      end
    end
    puts "HTU_MaskProbe: on."
    puts "  1. Chon vat  2. Bam nut XYZ  3. KEO mot grip  4. Buong ra"
    puts "  Roi HTU_MaskProbe.off va chep ca khoi tren ra."
    true
  end

  def self.off
    UI.stop_timer(@timer) if @timer
    @timer = nil
    true
  end
end
