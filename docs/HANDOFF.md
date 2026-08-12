# HTU ScalePlus — Handoff

Trạng thái tính đến 2026-08-12. Đọc file này trước khi sửa bất cứ thứ gì.

---

## 1. Plugin này là gì

Extension SketchUp, dựng lại từ **Curic Scale++ 1.1.2** bản bị RubyEncoder làm rối.
Toàn bộ cây nguồn hiện tại là Ruby thuần, đã đổi tên thành **HTU ScalePlus** và bỏ
hết phần kiểm tra license lẫn gọi về server của tác giả gốc.

Việc nó làm: bám lên **Scale tool có sẵn của SketchUp**, vẽ thêm số đo lên khung
bao của đối tượng đang chọn, cho gõ số trực tiếp vào số đo đó, giữ một danh sách
kích thước hay dùng, và khoá trục scale.

Yêu cầu SketchUp **23 trở lên** (dùng `Sketchup::Overlay`). Đang chạy trên SU 2026.

---

## 2. Cây file và thứ tự nạp

`htu_scaleplus.rb` (gốc archive) đăng ký extension, trỏ vào `htu_scaleplus/loader.rb`.
`loader.rb` require theo đúng thứ tự này — **giữ nguyên thứ tự khi reload**:

```
utils  main  group_lock  tool  dim_favorites  dim_menu  dim_add_dialog  scale_tool  dims  observer  overlay
```

| File | Việc |
|---|---|
| `utils.rb` | `Settings` (bọc read/write_default), hình học khung bao, vẽ chữ, `create_box` |
| `main.rb` | Chế độ khoá trục (`behavior_state` / `set_behavior` / `apply_behavior`), 6 `UI::Command`, `Typeface` |
| `group_lock.rb` | `GroupLock` — nhánh khoá trục cho selection **nhiều vật**: nhóm tạm, mask, dọn |
| `tool.rb` | Lớp cha `Tool`, 18 dòng |
| `dim_favorites.rb` | Danh sách kích thước đã lưu — **chủ sở hữu duy nhất** của phần lưu trữ |
| `dim_menu.rb` | Menu chuột phải trên một số đo |
| `dim_add_dialog.rb` | Cửa sổ `Dimensions` (HtmlDialog, HTML nhúng thẳng trong file) |
| `scale_tool.rb` | `ScalePPTool` — trái tim của plugin, 1137 dòng |
| `dims.rb` | `DimsUI` — dialog Vue cũ, vẫn nạp, `observer.rb` còn gọi tới |
| `observer.rb` | App / Tools / Selection observer, tự gắn overlay vào mỗi model |
| `overlay.rb` | `ScalePP2Overlay` — chuyển tiếp sự kiện và quyết định lúc nào push tool |

Có nhưng **không được nạp**: `radial_menu.rb`, `radial_menu/` (18 file), `lib/`,
`resources/`. Vẫn nằm trong .rbz. `pet_toolbar.rb` đã xoá.

---

## 3. Cơ chế cốt lõi — hiểu cái này trước

Plugin **không thay thế** Scale tool. Nó chạy song song:

- `ScalePP2Overlay` là một Overlay, được vẽ mỗi frame, nhận `onMouseMove`.
- Overlay giữ một `ScalePPTool`. Bình thường tool này **không** nằm trên tool stack —
  Scale tool gốc mới là tool đang chạy, và overlay gọi hộ `tool.draw` / `tool.onMouseMove`.
- Khi tool cần **bắt cú click**, overlay `push_tool` nó lên stack ([overlay.rb:31](../htu_scaleplus/overlay.rb#L31)).

Điều kiện push là `ScalePPTool#wants_push?` = `on_hover?` (con trỏ nằm trên chữ số đo)
`|| own_click?` (con trỏ ra ngoài khung grip).

**Hệ quả phải nhớ:** `push_tool` làm SketchUp suspend Scale tool gốc → grip xanh của
nó ngừng được vẽ. Mọi thứ nhìn bị "mất" khi rê chuột đều bắt nguồn từ đây. Overlay API
không có callback nút chuột, nên không có cách nào bắt click mà không chiếm stack.

`GRIP_MARGIN = 24`: trong khung bao trên màn hình cộng 24px thì cú click thuộc về
Scale tool gốc (có thể là grip); ngoài vùng đó thì thuộc về plugin. Đây là ranh giới
duy nhất chi phối toàn bộ phần retarget.

---

## 4. Các tính năng và chỗ code

**Số đo trên khung bao** — `scale_tool.rb#draw_dimensions`. Bật/tắt bằng nút
`Toggle show dimensions`. Cỡ chữ Small/Medium/Large trong menu chuột phải.

**Gõ số trực tiếp** — click vào con số → khoá trục đó, số được vẽ như đang bôi đen
(`EDIT_FILL`), gõ số mới là thay. `onKeyDown` chỉ *echo* để xem trước, VCB thật vẫn
nhận phím; gặp phím lạ thì tắt echo cho hết lần nhập (`@edit_echo = false`) để phần
xem trước không bao giờ nói dối. Xem `EDIT_KEYS` / `EDIT_IGNORED`.

**Danh sách kích thước đã lưu** — chuột phải vào số đo:

```
45 / 200 / 400      <- tick khi trùng kích thước hiện tại
--------
Open list...        <- mở cửa sổ Dimensions: thêm, xoá từng cái, xoá hết
Text size >         Small / Medium / Large
```

**Một danh sách chung cho cả ba trục**. Trục vẫn được truyền xuyên suốt vì chọn một
kích thước thì phải áp vào đúng trục vừa bấm — chỉ chỗ *lưu* là chung.

**Retarget** — đang scale vật A, click sang vật B là scale B luôn, click chỗ trống là
bỏ chọn. `pick_object` chỉ nhận group/component chưa khoá.

**Khoá trục** — 6 nút trên toolbar và trong menu `Plugins > HTU_ScalePlus`. Đặt
`no_scale_mask` cho definition: all=0, xyz=120, x=126, y=125, z=123. Chế độ là
**preference của máy**, `apply_behavior` áp nó vào mọi thứ được chọn sau đó — nên nó
sống qua component, qua file, qua phiên. Nút không bao giờ bị xám, tick bám theo chế
độ đã nhớ. Bấm lại nút đang bật = tắt về all.

**Khoá trục khi chọn nhiều vật** — `group_lock.rb`. `no_scale_mask` là thuộc tính của
**definition**, nên nó chỉ nói được cho một vật. Chọn hai vật thì SketchUp scale khung
bao hợp nhất — một cái lồng không thuộc definition nào, không mask nào chi phối, và cả
27 grip quay lại: chế độ vừa chọn trông như hỏng. `apply_behavior` vẫn ghi mask lên
từng vật, vẫn không có tác dụng, vì cái lồng không phải vật nào trong đó.

Cách bịt: cho cái lồng một definition riêng — gói selection vào **một group tạm**, đặt
mask đã nhớ lên definition của group đó, rồi để **Scale tool gốc** làm phần còn lại.
Grip, kéo, VCB, inference chạy nguyên vì với SketchUp đó vẫn chỉ là tool gốc đang scale
một group bình thường. Rời Scale tool là group tạm bị explode ngay.

Điều kiện gói (`GroupLock#wrappable?`): đang bật khoá trục (`behavior_state != 0`), chọn
**≥2** vật, và **mọi** vật được chọn đều `respond_to?(:definition)`. Selection có lẫn
face/edge thì **không gói** — kéo geometry thô ra khỏi context rồi nhét lại không phải
phép nghịch đảo (edge hàn lại vào thứ nó vừa chạm), người dùng sẽ nhận về một model khác
với cái họ vừa scale. Trường hợp đó giữ nguyên 27 grip như trước khi có file này.

Group tạm được **đóng dấu** attribute `HTU_ScalePlus / temp_scale_group`. Lý do là undo:
lần gói là một undo step riêng, nên undo quá cái scale sẽ **đặt group trở lại model** mà
không còn ai giữ tham chiếu tới nó. `GroupLock#sweep` là chỗ tìm ra những con đó — chạy
trước mỗi lần gói và trước mỗi lần save, nên số group tạm không bao giờ vượt quá một và
**không .skp nào bị ghi kèm nó**. `sweep` loại group đang sống ra **theo identity**: nó
mang đúng cùng cái dấu, cùng context, chỉ identity phân biệt được — thiếu chỗ này thì cú
re-pick Scale tool sẽ tự ăn mất group đang nằm dưới con trỏ.

Điểm dọn: đổi sang tool khác (qua `ScalePP2_ToolsOb#tool_changed`, **trên** chỗ kiểm tra
overlay — bỏ lại một group tạm còn tệ hơn không bao giờ tạo, nên unwrap phải chạy cả khi
overlay đã mất) và `ScalePPModelOb#onPreSaveModel`. `CameraOrbitTool` được `tool_changed`
return sớm từ trước, nên orbit bằng chuột giữa giữa lúc scale **không** làm mất group.
`wrap`/`unwrap` hoãn một tick (`UI.start_timer(0)`) đúng lý do `apply_behavior` hoãn: nó
sửa model, và một sửa đổi từ trong observer callback có thể rơi vào giữa operation đã gây
ra callback đó. `onPreSaveModel` thì chạy **inline** — save xảy ra ngay sau đó, timer sẽ
nổ quá muộn.

**Orbit / pan / zoom giữa lúc scale không mất gì** — `ScalePP2_ToolsOb::NAVIGATION`
trong `observer.rb`. SketchUp cài cả ba thứ này thành **tool change**: giữ chuột giữa là
active tool thành `CameraOrbitTool`, shift+giữa thành `CameraPanTool`, thả ra thì trả
Scale tool lại. Plugin móc mọi thứ vào `onActiveToolChanged`, nên mỗi cú đó trông đúng
như người dùng rời Scale tool thật.

Trước đây **chỉ `CameraOrbitTool`** được chặn. Nên pan hay zoom mất một lúc **ba** thứ:
số đo ngừng được vẽ, số đo đang gõ mất cả khoá trục lẫn nội dung đã gõ
(`ScalePPTool#deactivate` gọi `unlock_axis`), và group tạm của `GroupLock` bị explode
ngay giữa lúc đang kéo grip.

Guard khớp theo **keyword** (`/Orbit|Pan|Zoom|Walk|Around|Camera/`) chứ không so cả tên,
vì `fix_mac_tool_name` tồn tại chính vì macOS báo tên bị cắt mất phần đầu. **Giới hạn đã
biết, không phải sót:** các truncation đã ghi trong `fix_mac_tool_name` cắt tới mức `"ool"`
cho `MoveTool` — không keyword nào sống nổi qua đó. Tên như vậy sẽ bị đọc là tool change
thật, tức mất số đo; đó là hướng fail an toàn. Cách sửa gốc là dùng `tool_id` (số, giống
nhau trên cả hai nền tảng), nhưng phải bắt được id thật từ một máy mac trước — id đoán
bừa còn tệ hơn keyword.

Guard đặt trong `ScalePP2_ToolsOb#tool_changed`, **trên** cả `GroupLock.tool_changed` lẫn
`overlay.tool_changed`, nên một chỗ chặn là đủ cho cả hai. `onActiveToolChanged` cũng
**không** ghi tên navigation vào `last_tool_name`: `Overlay#start` phát lại giá trị đó, và
phát lại `"CameraOrbitTool"` là overlay dựng lại xong với Scale tool đang tắt.

`PLUGIN.navigation?(tên)` và `PLUGIN.navigating?` (hỏi `tools.active_tool_name`, tức
trạng thái **thật** của stack) đều ở module level trong `observer.rb` — overlay cần bản
thứ hai vì `onMouseMove` không được truyền tên tool nào.

**Grip gốc trong lúc navigation** — `overlay.rb`. Hai thứ không được xảy ra khi người dùng
đang kéo camera, và trước đây xảy ra cả hai:

- Orbit làm khung bao **trượt trên màn hình dưới con trỏ đang giữ im**, nên `own_click?`
  tự lật thành true → overlay `push_tool` → Scale tool gốc bị suspend, **grip xanh mất
  giữa lúc orbit**. Đúng cái người dùng đang nhìn.
- `ScalePPTool#onMouseMove` có thể quyết định trả stack lại, nhưng `pop_tool` pop **thứ
  đang ở trên cùng** — giữa navigation đó là camera tool của SketchUp. Tức là **huỷ luôn
  cú orbit** người dùng đang làm.

Nên `onMouseMove` giờ chỉ ghi lại `@mouse` rồi return khi `PLUGIN.navigating?`. Không phải
hoãn: `Overlay#navigation_finished` **phát lại toàn bộ quyết định** ngay khi nhả camera.

Phần push/pop đã tách ra `Overlay#dispatch_mouse` chính vì lý do đó. Pop nằm **trong**
`ScalePPTool#onMouseMove`, nên trước khi có chỗ tách này thì grip gốc còn bị suspend sau
orbit cho tới khi người dùng rê chuột — con trỏ để yên hẳn thì **không bao giờ** lấy lại
được. `navigation_finished` chạy `dispatch_mouse` với `@mouse` cuối cùng + camera mới,
hoãn một tick vì lúc callback chạy SketchUp vẫn đang tháo camera tool khỏi stack.

Ai gọi: `tool_changed` giữ cờ `@navigating`, thấy tên navigation thì bật cờ và return;
lần sau gặp tên thật thì đó là **resume** → gọi `navigation_finished` một lần. Đổi tool
bình thường không phải resume — phát lại ở đó là push tool lên cái stack người dùng vừa
cố ý rời khỏi.

**SketchUp bỏ cả grip lẫn viền vàng, ở mọi gesture nó báo là tool change.** Đo trên
SU 2026 bằng cách xem lại video capture từng frame — không suy luận, vì suy luận đã sai
hai lần ở đúng chỗ này:

| Gesture | Grip xanh | Viền vàng khung bao |
|---|---|---|
| orbit | mất → plugin tô bù | mất → plugin vẽ bù |
| pan (`CameraDollyTool`) | **mất** → plugin tô bù | mất → plugin vẽ bù |
| zoom (con lăn) | còn | còn — không đổi active tool, `navigating?` false |

Nên **một điều kiện cho cả hai**: `active_itself? || PLUGIN.navigating?`, ở
`draw_scale_points` (`fill`) và `draw_bounds?`.

**Ngõ cụt đã đi rồi, đừng đi lại:** từng có `GRIPLESS_TOOLS = /Orbit/` với giả thuyết
"orbit mất grip, pan giữ grip". **Sai.** Cái làm tưởng vậy: lúc báo "pan grip vẫn còn" thì
`fill` đang bật cho mọi navigation, tức **chính plugin tô ra những grip đó**. Thu hẹp về
orbit là pan còn trơ 6 ô xám rỗng. Frame capture của một cú pan cho thấy chỗ đáng ra có
grip chỉ còn viền xám plugin vẽ, **không có gì xanh bên trong**.

Zoom con lăn không cần entry ở đâu cả: nó **không phải tool change**, `navigating?` false,
không tô gì, grip thật lộ qua. Đó chính là thứ khiến fill không bao giờ lấp được grip thật
— kể cả màu nó đổi khi hover.

Viền vàng do `draw_selected_bounds` vẽ (`"yellow"`, width 3) — hàm có sẵn, trước chỉ bị
chặn bởi `active_itself?`. Mất nó thì SketchUp lùi về màu selection xanh dương thường, tức
nhìn như đã rời Scale tool.

`navigating?` hỏi stack **thật**, nên cả hai tắt ngay ở đúng frame SketchUp vẽ lại — không
có khoảng nào vẽ đè. Đây là lý do không dùng cờ `@navigating` của observer (tắt trễ một tick).

**Giới hạn, có từ trước:** thứ tô là 6 grip mặt do `bounds_center_lines` sinh ra. Đang khoá
trục thì đúng bằng những gì SketchUp hiện. Không khoá thì tool gốc hiện đủ 27 và 21 cái còn
lại vắng mặt suốt lúc di chuyển camera — đúng bản copy thiếu mà chỗ này vẫn vẽ mỗi khi giữ
stack, không phải hồi quy mới.

**Tô grip** — khi tool giữ stack, `draw_scale_points` tự tô ruột ô grip bằng
`GRIP_FILL = [0,255,0]` (đo từ grip thật của SketchUp) rồi vẽ viền xám lên trên, để
grip không trông như bị tắt. Lúc không giữ stack thì **không** tô — grip thật đang ở
dưới, tô vào là lấp mất cả màu nó đổi khi rê chuột lên.

---

## 5. Chỗ lưu dữ liệu

Tất cả qua `Sketchup.read_default` / `write_default`. Không có gì nằm trong file .skp
nữa (trừ `no_scale_mask`, vốn là thuộc tính thật của component).

Ngoại lệ duy nhất là attribute `HTU_ScalePlus / temp_scale_group` trên group tạm của
`GroupLock`. Nó **cố tình** không bao giờ tới được file: `onPreSaveModel` explode group
trước khi save, `sweep` dọn nốt con nào sót lại từ undo. Nếu bạn mở một .skp và thấy
attribute này, nghĩa là một trong hai chỗ đó đã hỏng.

| Section | Key | Nội dung |
|---|---|---|
| `HTU ScalePlus` | `dims` | Danh sách kích thước, **đơn vị inch**, nối bằng dấu phẩy |
| `HTU ScalePlus` | `dim_text_size` | 0 / 1 / 2 |
| `HTU ScalePlus` | `dim_offset` | 20 |
| `HTU ScalePlus` | `show_dim` | true/false |
| `htu_behavior` | `state` | 0 / 120 / 126 / 125 / 123 |

Lưu bằng inch để danh sách nhập trong file mm vẫn đọc đúng ở file inch.

`DimFavorites.adopt_legacy` chạy **một lần**, khi key `dims` chưa từng được ghi: nó
gom cả ba key per-axis cũ (`lenx_dims` / `leny_dims` / `lenz_dims`) lẫn attribute
trong component của file cũ, trộn lại rồi ghi vào `dims`. Điều kiện là "chưa từng
ghi" chứ không phải "đang rỗng" — để người dùng xoá sạch danh sách thì nó ở yên rỗng.

Trên máy: `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\SharedPreferences.json` (ghi ngay)
và `%LOCALAPPDATA%\...\PrivatePreferences.json` (giữ trong RAM, ghi lúc thoát).

---

## 6. Build và test

```
ruby build.rb
```

Chạy `ruby -c` cho toàn bộ 44 file, rồi 10 gate. Fail bất kỳ gate nào là **không**
đóng gói. Ra `dist/htu_scaleplus-1.2.rbz` (62 file, ~486 KB).

Version nằm **một chỗ duy nhất**: `PLUGIN_VERSION` trong `htu_scaleplus.rb`. `build.rb`
đọc nó bằng regex để đặt tên .rbz, nên đổi ở đó là đủ cho phần đóng gói. Con số `1.1.2`
còn lại trong `README_BUILD.md` và HANDOFF §1 là **version của Curic Scale++ gốc** — thứ
bản này được dựng lại từ đó — không phải version của plugin này, đừng sửa theo.

| Gate | File |
|---|---|
| dropped-param scan | `test/dropped_param_scan.rb` |
| load | `test/load_test.rb` |
| runtime | `test/runtime_test.rb` |
| dim favorites | `test/dim_favorites_test.rb` |
| dim menu | `test/dim_menu_test.rb` |
| dim edit | `test/dim_edit_test.rb` |
| add dialog | `test/dim_add_dialog_test.rb` |
| retarget | `test/retarget_test.rb` |
| behavior | `test/behavior_test.rb` |
| group lock | `test/group_lock_test.rb` |
| navigation | `test/navigation_test.rb` |
| text size | `test/text_size_persistence_test.rb` |

Chạy lẻ: `ruby test/<tên>.rb`.

### `test/su_shim.rb` — đọc kỹ phần này

Toàn bộ test chạy bằng Ruby thường, không cần mở SketchUp. `su_shim.rb` giả lập API.

**Bài học lặp đi lặp lại suốt dự án: gần như mỗi lần thêm test là phải nâng độ trung
thực của shim trước.** Shim dễ dãi hơn SketchUp thật thì test xanh mà code vẫn hỏng.
Những chỗ đã phải sửa vì lý do đó:

- `screen_coords` từng gộp mọi điểm về gốc toạ độ → retarget không thể test được
- `screen_coords` từng chỉ nhận `Point3d`, SketchUp thật nhận cả `[x,y,z]`
- `active_view` từng không có model → `view.model.selection` chết
- `draw` / `draw2d` từng vứt tham số → không phân biệt được tô đặc hay chỉ vẽ viền
- `draw_text` **cố tình** raise `TypeError` với key không phải Symbol, đúng như SketchUp
- `Sketchup::Overlay` từng **không có** `enabled=`. `observer.rb#add_overlay` gán
  `overlay.enabled = true` rồi `rescue` nuốt luôn NoMethodError → mọi nhánh gated trên
  `enabled?` không test được. Nay có cả writer lẫn `valid?`
- `Tools#active_tool_name` giờ **ghi được**. "Người dùng đang orbit" không phải trạng thái
  test tới được bằng cách push một tool Ruby — camera tool của SketchUp là native, không
  bao giờ xuất hiện trên cái stack shim mô phỏng
- `InputPoint` từng chỉ có `initialize` → `@ip_mouse.pick` trong `dispatch_mouse` chết,
  nghĩa là **cả đường dispatch của overlay không test được**
- `model.entities` từng trả `[]`, entity không có `valid?`, không có `Entities#add_group`
  lẫn `Group#explode` → không test được `GroupLock`. Nay là `Entities` thật: `add_group`
  **dời** entity vào group (không copy, để lỗi hai chỗ cùng giữ không lọt), `explode` trả
  về danh sách con đúng như API thật, `valid?` thành false sau khi bị xoá

Nguyên tắc: nếu một lỗi thật lọt qua được shim, sửa shim trước, rồi mới viết test.

---

## 7. Vòng lặp phát triển

`dev/htu_scaleplus_reload.rb` đã được đặt sẵn trong Plugins. Trong Ruby Console:

```ruby
HTU_ScalePlusReload.run
```

Nó copy file từ `E:/htu_scaleplus/htu_scaleplus` đè lên bản đang cài, bỏ tool đang
chạy, `load` lại các sub-file **đúng thứ tự loader.rb**, dựng lại overlay, in MD5.

Vì sao phải copy trước: SketchUp đang chạy **bản đã cài**, reload bản trong repo là
cách kinh điển để đuổi theo một lỗi đã sửa rồi.

Cần khởi động lại SketchUp khi: đổi `loader.rb` phần dựng menu/toolbar, đổi
`htu_scaleplus.rb`, hoặc thêm file mới vào `SUB_FILES`.

Đường dẫn bản cài:
`%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\htu_scaleplus\`

---

## 8. Việc còn treo

**Chưa commit.** Không có gì trong phiên làm việc này được commit. `git status` đang
bẩn: 2 file xoá (`pet_toolbar.rb`, .rbz cũ), 4 file mới trong `htu_scaleplus/`
(`dim_*.rb` + `group_lock.rb`), 9 test mới, cùng `dev/` `docs/` `dist/`.
HEAD vẫn là `cd9395b`. Version đã lên **1.2**.

**Grip lúc orbit / pan: ĐÃ XONG, người dùng xác nhận trên SU 2026.** Cả grip xanh lẫn viền
vàng đều còn nguyên khi orbit và khi pan. Giữ nguyên phần dưới vì nó là hồ sơ cách tìm ra,
và §4 ghi ngõ cụt để không ai đi lại.

Số đo từ `dev/htu_nav_probe.rb` (chọn 1 group, bấm S, orbit):

```
tool=RubyTool         active=true   ov=4  grips=4  fill=true
tool=CameraOrbitTool  active=false  ov=10 grips=0  fill=true
```

`ov=10` — `Overlay#draw` **vẫn được gọi** suốt lúc orbit, nên chưa bao giờ là tường native.
`grips=0` vì `active?` đã false. Nguyên nhân là `"RubyTool"` và `Tool#active=`, xem §4.

Sau khi sửa, đo lại (một gesture mỗi lần, probe đã hết nói dối):

```
tool=ScaleTool        active=true flag=true at=nil   ov=1  grips=1  fill=false
tool=CameraOrbitTool  active=true flag=true at=nil   ov=10 grips=10 fill=true
tool=RubyTool         active=true flag=true at=ours  ov=2  grips=2  fill=true
```

`ov == grips` suốt lúc orbit — mỗi lần overlay vẽ đều tới được `draw_scale_points`, và
`fill=true`. **Cơ chế đã chạy đúng.**

`at=nil` lúc orbit, tức `Tools#active_tool` trả nil khi camera tool native chiếm đỉnh —
nên `at != tool` không phải đường mất grip trong *lần đo này*. Nhưng lần đó tool **chưa
nằm trên stack** trước khi orbit. Trường hợp "orbit khi plugin đang giữ stack" chưa đo
được, và nếu lúc đó `active_tool` trả về `ours` thì `at != tool` thành false và grip mất
lần nữa. Đó là lý do `Overlay#draw` giữ nhánh `navigating ||` — **không phải code dư**.

Đo, đừng suy luận. Chuyện này đã sai bốn lần vì suy luận: giả định "mọi navigation đều mất
grip" (chỉ orbit đúng), tưởng SketchUp không vẽ overlay (nó vẫn vẽ), tin `CameraPanTool` là
tên thật (là `CameraDollyTool`), và tưởng "mất" nghĩa là mất grip (còn mất **viền vàng**
nữa, đó mới là thứ sót lại sau cùng).

**Video capture là công cụ đo tốt nhất cho phần nhìn.** Không có ffmpeg trên PATH, nhưng
`imageio_ffmpeg` có kèm binary:

```
C:\Users\Phucs\AppData\Roaming\Python\Python314\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe
```

Tách 3 fps rồi crop-zoom quanh vật là đủ thấy khác biệt màu mà mắt bỏ qua khi xem chạy:

```
ffmpeg -i cap.mp4 -vf "fps=3" f%03d.png
ffmpeg -i f020.png -vf "crop=420:280:640:400,scale=iw*2.2:ih*2.2:flags=neighbor" crop020.png
```

**Probe từng nói dối, đã sửa.** `dev/htu_nav_probe.rb` bản đầu đếm bằng `alias_method`, và
`HTU_ScalePlusReload.run` nạp lại `overlay.rb` làm mất wrapper — trong khi alias
`draw_unprobed` còn nguyên nên guard bảo "đã bọc rồi" và không bọc lại. Mọi cột đếm về 0
sau mỗi reload, plugin trông như ngừng vẽ hẳn. Nay đếm bằng `prepend`: module prepend sống
qua việc class được nạp lại (`super` vẫn tới bản mới), và prepend hai lần là no-op. **Một
dụng cụ đo nói dối còn tệ hơn không có.**

```ruby
load "E:/htu_scaleplus/dev/htu_nav_probe.rb"
HTU_NavProbe.on     # chon 1 group, bam S, roi orbit
HTU_NavProbe.off
```

Cách đọc nằm trong header file đó. `at=` là cột duy nhất còn chưa biết: nếu nó báo `ours`
trong lúc orbit thì `Tools#active_tool` vẫn trả về tool đã bị suspend, tức `at != tool` là
đường **thứ hai** làm mất grip — đó là lý do điều kiện đó giờ cũng pass khi `navigating?`.

**Tên tool: đã đo được 4, còn lại vẫn là tài liệu.** Probe trên SU 2026 báo về:

| Tên thật | Khi nào |
|---|---|
| `ScaleTool` | bấm S |
| `RubyTool` | **plugin tự push tool của nó** — xem §4, đây là gốc vụ orbit mất grip |
| `CameraOrbitTool` | orbit chuột giữa |
| `CameraDollyTool` | pan / zoom |

`CameraDollyTool` là cú bất ngờ: tài liệu ghi `CameraPanTool`, mà SketchUp **không báo tên
đó bao giờ**. Nó vẫn bị chặn đúng, nhưng **chỉ vì** guard khớp theo keyword và `Camera` là
một keyword — một danh sách tên chính xác đã bỏ sót nó và làm pan mất số đo. Đây là lần
thứ hai cách khớp lỏng cứu được một tên không đoán ra; giữ nguyên nó.

Bốn tên còn lại trong `test/navigation_test.rb` (`CameraZoomTool`,
`CameraZoomWindowTool`, `WalkTool`, `LookAroundTool`, `PositionCameraTool`) vẫn là tài
liệu, **chưa ai xác nhận**. Giữ vì rộng hơn là hướng an toàn, nhưng đừng đọc như đã kiểm.

Chưa bắt được `tool_id` — đó vẫn là cách sửa gốc cho vụ macOS cắt tên ở §4. Probe in được
id nếu thêm, hoặc dùng observer 4 dòng:

```ruby
class TN < Sketchup::ToolsObserver
  def onActiveToolChanged(_t, name, id); puts "#{name}  id=#{id}"; end
end
Sketchup.active_model.tools.add_observer(TN.new)
```

**`GroupLock` chưa chạy thử trong SketchUp thật.** 11 gate xanh trên shim, nhưng ba điều
chỉ SketchUp trả lời được: (1) group tạm mask 120 có thật sự ra đúng 6 grip khi trước đó
đang chọn nhiều vật hay không; (2) `send_action("selectScaleTool:")` có đủ để Scale tool
đọc lại selection mới hay còn cần thêm; (3) chuỗi undo sau khi scale xong trông thế nào —
`sweep` là lưới an toàn cho việc đó, nhưng số lần bấm Ctrl+Z người dùng phải chịu thì
chưa ai đếm. Chạy `HTU_ScalePlusReload.run` rồi chọn 2 group, bật nút XYZ, bấm S.

**Rác còn trong .rbz** — `lib/` (3 file), `resources/`, `radial_menu/` (18 file),
`radial_menu.rb`. Không file nào được require. Bỏ khỏi `EXCLUDE_DIRS` là gói nhẹ đi
đáng kể, nhưng chưa ai xác nhận `dims.rb`/`ui/` có gián tiếp đụng tới không.

**`utils.rb:238`** vẫn là `@text_typeface.draw2d_text(view, point, text.to_s, {nil => options})`.
Key `nil` này SketchUp thật sẽ raise `TypeError`. Test không chạm tới nhánh đó nên
gate vẫn xanh. Sửa thì nhiều khả năng là `options` trực tiếp, nhưng chưa kiểm chứng.

**`overlay.rb:70`** — `fit_to_length = false` là công tắc tắt cứng, cả khối dưới nó
là code chết. Chưa rõ nó từng làm gì.

**`dims.rb` / `DimsUI`** — dialog Vue cũ, vẫn nạp và `observer.rb` vẫn gọi
`DimsUI.dialog`. Không có lối vào nào từ menu nữa. Có thể là ứng viên xoá.

**`RotationGripsInMoveTool` = false** trong prefs của máy người dùng — họ tự tắt lúc
đi tìm dòng chữ đỏ ở mục dưới, không liên quan plugin. Chưa bật lại.

---

## 9. Ngõ cụt — đừng đi lại

**Dòng chữ đỏ "Select a grip and move it to scale." của SketchUp 2026 trên viewport.**
Đã tốn rất nhiều thời gian, **không xoá được**. Đã loại trừ dứt điểm:

- Không phải plugin vẽ (grep cả repo lẫn Plugins folder)
- Không phải `SB_PROMPT` — đã ghi đè 10 lần/giây, vẫn hiện
- Không phải ô prompt trên status bar — đặt `PromptVisible: false`, sống qua restart, vẫn hiện
- Không phải `ShowInferenceTips` — key này **không tồn tại** trong bất kỳ file prefs
  nào, và `write_default` cũng không tạo ra nó
- Không có công tắc nào trong Preferences > Accessibility / Drawing / General
  (đã diff prefs trước–sau, chỉ đổi mỗi timestamp)

Toàn bộ máy móc `clear_tool_prompt` / `start_prompt_guard` đã được gỡ bỏ. Nếu ai định
làm lại, đọc lại đoạn này trước.

**Menu Del vẽ tay.** Đã dựng một panel tự vẽ để xoá nhiều item mà menu không tắt.
Không bao giờ giống menu native đủ để chấp nhận được. Đã revert; vai trò đó giờ thuộc
về cửa sổ `Dimensions`, và nó làm tốt hơn.

---

## 10. Quy ước code

- Comment giải thích **vì sao**, nhất là ở chỗ có bẫy hoặc quyết định đã cân nhắc.
  Đây là quy ước xuyên suốt file — bám theo nó.
- Nhiều chỗ format lệch (block `do...end` thụt lề lạ) là dấu vết của bản deobfuscate.
  Đừng format lại hàng loạt, diff sẽ vô nghĩa.
- Mọi thứ đụng tới danh sách kích thước phải đi qua `DimFavorites`. Không ai được
  `read_default` key `dims` trực tiếp.
- Vẽ mỗi frame thì phải `rescue` — một exception trong `draw` sẽ spam Ruby Console.
