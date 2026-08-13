# HTU ScalePlus — Handoff

Trạng thái tính đến 2026-08-12. Đọc file này trước khi sửa bất cứ thứ gì.

---

## 1. Plugin này là gì

Extension SketchUp, dựng lại từ **Curic Scale++ 1.1.2** bản bị RubyEncoder làm rối.
Toàn bộ cây nguồn hiện tại là Ruby thuần, đã đổi tên thành **HTU ScalePlus** và bỏ
hết phần kiểm tra license lẫn gọi về server của tác giả gốc.

Chỗ cuối cùng gọi về server đã bỏ trong đợt kiểm tra trước khi giao khách: `module
Update` trong `utils.rb` (~270 dòng) — tự tải bản mới từ `curic.io`, có cả dialog
"Download and Install" và `UI.openURL`. Hai chỗ gọi nó (menu "Check for Update" và
timer 10 giây lúc khởi động) đã bỏ từ trước, nhưng **code vẫn ship và vẫn nạp vào
memory**, và vẫn tải-cài được file nếu có gì gọi tới. `curic_icon.png` cũng đã xoá.
`load_test.rb` khoá lại bằng hai check: `Update` không được định nghĩa, và **không
dòng code sống nào** (comment thì được) nhắc tới `curic` — check thứ hai in ra đúng
file:dòng khi bị vi phạm.

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
| `scale_tool.rb` | `ScalePPTool` — trái tim của plugin, 1258 dòng |
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

Điều kiện push là `ScalePPTool#on_hover?` — con trỏ nằm **trên chữ số đo**, và chỉ thế.

**Hệ quả phải nhớ:** `push_tool` làm SketchUp suspend Scale tool gốc → grip xanh của
nó ngừng được vẽ. Mọi thứ nhìn bị "mất" khi rê chuột đều bắt nguồn từ đây. Overlay API
không có callback nút chuột, nên không có cách nào bắt click mà không chiếm stack.

Vì thế tool phải giữ stack **đúng bằng khoảng thời gian nó cần con chuột, không hơn một
frame** — nhả ra ngay khi con trỏ rời nhãn, trừ lúc đang có trục bị khoá và người dùng
đang gõ số (một cú lay chuột sẽ ném đi những gì vừa gõ). Chốt ở `dim_edit_test.rb` mục
"holding the tool stack, and letting go".

Từng có lý do thứ hai để chiếm stack — **retarget**, click sang vật khác là scale vật đó.
Đã bỏ, xem §4. Cái nó để lại và **vẫn còn cần**: grip thay thế, vì lý do thứ nhất vẫn
khiến grip gốc tắt mỗi lần con trỏ đậu lên một nhãn.

---

## 4. Các tính năng và chỗ code

**Số đo trên khung bao** — `scale_tool.rb#draw_dimensions`. Bật/tắt bằng nút
`Toggle show dimensions`. Cỡ chữ Small/Medium/Large trong menu chuột phải.

**Gõ số trực tiếp** — click vào con số → khoá trục đó, số được vẽ như đang bôi đen
(`EDIT_FILL`), gõ số mới là thay. `onKeyDown` chỉ *echo* để xem trước, VCB thật vẫn
nhận phím; gặp phím lạ thì tắt echo cho hết lần nhập (`@edit_echo = false`) để phần
xem trước không bao giờ nói dối. Xem `EDIT_KEYS` / `EDIT_IGNORED`.

**Khi nào một nhãn số đo vắng mặt** — `compute_dimensions_lines`. Số đo nhìn *đúng dọc
theo nó* chỉ là một điểm: không vẽ được, không bấm được, nên nó bị bỏ. Nhánh x và y bỏ
bằng cách kiểm `vec_offset.parallel?(direction)` rồi lùi về `camera.up`; nhánh z bỏ thẳng.

Nhánh z từng kiểm **`Z_AXIS` của thế giới** thay vì `vecz` — cạnh thứ ba của chính khung
bao. Hai thứ đó chỉ trùng khi vật không quay, nên sai cả hai chiều:

| | trước | sau |
|---|---|---|
| vật quay, cạnh thứ ba nằm ngang, nhìn từ trên | **mất nhãn** dù vẽ được bình thường — và mất luôn đường gõ lại số đó | có nhãn |
| camera nhìn dọc cạnh thứ ba đã quay | lọt guard, `vecz.cross(direction)` = **vector 0** | bỏ sạch |

Đo được ở `dim_edit_test.rb` mục "which labels exist, and why one can be missing". Trả
guard về `Z_AXIS` làm đỏ 3 check.

**Sửa số đo có thật sự resize không** — mục "typing a number actually resizes the object",
mới có được sau khi `Geom::Transformation` trong shim thành ma trận thật (§6). Trước đó
**không gate nào chứng minh gõ số làm vật đổi kích thước**; cả cụm test số đo chỉ chốt cái
máy trạng thái đằng trước. `no_scale_mask` không chi phối đường này: nó chỉ nói về grip của
SketchUp, còn transformation đặt từ Ruby thì mọi mask đều đổi được — có check cho cả 5 mask.

**Danh sách kích thước đã lưu** — chuột phải vào số đo:

```
45 / 200 / 400          <- tick khi trùng kích thước hiện tại
--------
Open list...            <- mở cửa sổ Dimensions: thêm, xoá từng cái, xoá hết
Text size >             Small / Medium / Large
```

Khi **chưa lưu gì**, menu chỉ còn đúng hai dòng cuối — `Open list...` và
`Text size` — **không có gạch ngang** ở trên chúng.

**Bốn thứ trong menu này là của Scale++ gốc và từng bị mất** trong lúc viết
`dim_menu.rb`: hai gợi ý nửa/đôi, hai heading xám, `Referenced Dimensions`, và
`Show Manager`. Nặng nhất là gợi ý nửa/đôi — máy mới cài chưa lưu gì thì đó là
**toàn bộ** những gì menu có, mất nó thì chuột phải ra một menu không có kích thước
nào để bấm. Cả bốn đã được trả lại trong lần audit trước release.

**Rồi CẢ BỐN bị bỏ lại, 2026-08-13, theo yêu cầu — quyết định, không phải lỗi.**
Khác hẳn lần trước: lần trước là mất mà không ai biết, lần này là chọn. Menu cuối
cùng chỉ còn: danh sách đã lưu, `Open list...`, `Text size`.

- `Favorite Dimensions` — heading xám nằm trên khối đầu tiên. Khối đó ở ngay đỉnh
  menu và các kích thước chính là *lý do* menu tồn tại, nên cái label là một dòng
  không bấm được để giải thích điều đã rõ.
- `Show Manager` — mở dialog Vue `DimsUI` cũ. `Open list...` ngay trên nó làm đúng
  việc đó trong một cửa sổ viết riêng cho việc đó. **Hệ quả cần biết:** giờ không còn
  lối nào mở `DimsUI`, nên 11 file đó ship mà không ai tới được, và các lệnh refresh
  trong `observer.rb` không tìm thấy dialog nào để refresh (`DimsUI.dialog` = nil,
  nhánh đó tự thoát — không raise). Xem §8.
- **Hai gợi ý nửa/đôi** `225 (x0.5)` / `900 (x2.0)` — một phép nhân đưa ra dưới dạng
  kích thước, mà kéo grip thì đã làm đúng việc đó rồi. Đã hỏi trước khi bỏ vì đó là
  thứ *duy nhất* menu đưa ra khi chưa lưu gì.
  Giá của nó đã bị tôi đánh giá **sai hai lần theo hai hướng ngược nhau**, nên ghi lại
  cho rõ: lúc hỏi tôi nói khách phải tự mở `Open list...` lưu tay trước; rồi phát hiện
  gõ số đo là tự lưu nên nói lại là giá nhỏ hơn nhiều; **rồi chính việc tự lưu đó bị bỏ
  theo yêu cầu** (mục dưới). Kết luận cuối, và lần này khớp với code: **máy mới cài,
  menu chuột phải rỗng cho tới khi tự mở cửa sổ và nhập giá trị.** Đúng như câu tôi nói
  đầu tiên — nhưng lúc đó nó chưa đúng.

- **`Referenced Dimensions` + các dòng `(in model)`** — kích thước mà các instance
  khác của cùng definition đang có. Nghe hay, dùng thì dở, và **chính ảnh chụp của
  người dùng là bằng chứng**: khối đó hiện ra `~ 592 (in model)`. Dấu `~` là SketchUp
  nói con số **không tròn được** ở độ chính xác của model — nghĩa là cái vật bên cạnh
  đã bị kéo grip tự do, và menu đem đúng con số rác đó ra mời. Không ai chọn 592 có
  chủ đích. Danh sách đã lưu là câu trả lời *có chọn lọc* cho đúng câu hỏi đó.
  Xoá kèm: `ScalePPTool#referenced_dims` (26 dòng), `#same_dc_definition` (17 dòng),
  `DimMenu.add_referenced_items` và `DimMenu.add_heading`.

Kéo theo hai thứ không ai yêu cầu nhưng là hệ quả trực tiếp:

**Gạch ngang có điều kiện.** Gạch ngang là để *chia*, nên nó cần có khối ở cả hai bên;
mất khối gợi ý thì máy mới cài không còn gì ở trên nó, và một menu mở ra bằng một
đường kẻ ngang đọc như một mục vẽ lỗi. Giờ chỉ còn một điều kiện duy nhất —
`unless values.empty?` — vì chỉ còn một khối. (`add_referenced_items` từng phải *trả
về* nó có thêm gì hay không, và nhận cờ `divide`; cả cơ chế đó đi theo nó.)

**`Utils#definition_paths` và `#get_path` giờ không còn ai gọi.** Đó là utility của
plugin gốc, không phải thứ thêm vào cho tính năng này, nên **để lại** giống
`listbox.rb` — xem §8. `utils.rb` có **hai bản** của cặp này (dòng ~82/90 và ~330/338),
cũng là chuyện của bản gốc.

Cũng phải chú ý, và đây là bẫy đã thật sự sập một lần: check duy nhất chứng minh **bấm
một kích thước thì vật đổi kích thước** nằm trên chính cái gợi ý nửa/đôi — xoá gợi ý
mà không nhìn thì mất luôn cả đường `apply_dim_value`. Đã chuyển sang kích thước đã
lưu trước khi xoá.

Cả bốn đều bị chốt bằng check trong `dim_menu_test.rb`, **và chốt cả phần code chứ
không chỉ phần menu**: một khối không tới được nhưng code vẫn còn thì chỉ cách một lời
gọi là quay lại. Có check `!tool.respond_to?(:referenced_dims)` và
`!MENU.respond_to?(:add_heading)`.

Fixture `two_instances` **giữ lại và có check riêng cho chính nó**: các check "không
hiện gì" chỉ có giá trị nếu chạy trên đúng cái model từng sinh ra khối đó — hai
instance của MỘT definition ở hai kích thước. Không hiện gì trên model rỗng thì chứng
minh được số không. Mutation test đã xác nhận: làm hỏng fixture (bỏ scale instance thứ
hai) là check đó đỏ. Cũng vì vậy mà **fidelity của shim** (`#instances`, `#parent`,
`InstancePath#transformation`) **giữ nguyên** — shim đúng hơn thì không phải là chi phí.

Mutation test: 6 mutation, **6 đỏ**, không cái nào sống sót.

**Một danh sách chung cho cả ba trục**. Trục vẫn được truyền xuyên suốt vì chọn một
kích thước thì phải áp vào đúng trục vừa bấm — chỉ chỗ *lưu* là chung.

**Gõ một số đo thì số đó KHÔNG vào danh sách. Bỏ theo yêu cầu, 2026-08-13.**
Danh sách giờ chỉ chứa những gì người dùng **cố ý** đặt vào, qua cửa sổ Dimensions —
mà đó cũng là chỗ duy nhất lấy giá trị ra được, nên một danh sách tự đầy là một danh
sách phải đi dọn.

Cả chuyện này diễn ra trong ba nhịp trong cùng một ngày, ghi lại vì nhịp giữa là chỗ
dễ đi lại vào:

1. Người dùng yêu cầu "gõ số đo thì tự thêm vào danh sách". Tôi bắt đầu viết một hàm
   `remember_dim_value` mới — rồi **gỡ ra và test vẫn 6/6 xanh**. Tính năng đã có sẵn:
   `set_dim_value` kết thúc bằng `save_dim_to_object`, mà cái đó (`scale_tool.rb:11`)
   chính là `DimFavorites.add`. Hành vi Curic Scale++ gốc. **Bài học thật:** đường
   `apply_dim_value` → `set_dim` → `set_dim_value` lúc đó **không có một test nào** cho
   việc lưu, nên một tính năng đang chạy trông y như chưa làm.
2. Chỗ thật sự thiếu: chỉ **nhánh một vật** lưu, nhánh chọn nhiều vật (qua
   `transform_entities`) thì không — cùng một động tác gõ mà có lưu hay không lại tuỳ
   đang chọn mấy vật. Đã bù vào.
3. **Rồi bỏ cả hai**, theo yêu cầu. `set_dim_value` giờ chỉ resize. Các biến `name =
   "lenx"` … cũng đi theo, vì trong method đó không còn ai dùng.

`PLUGIN.save_dim_to_object` **giữ lại**: `dims.rb:109` còn gọi cho lệnh lưu *tường minh*
của dialog Vue — đó là người dùng yêu cầu lưu, không phải tác dụng phụ của resize.
(DimsUI hiện không còn lối vào, xem §8 — giữ vì xoá là việc riêng, không phải vì còn ai
tới được.)

**Mọi check ở đây đều cần positive control cùng dòng.** "Danh sách không lớn lên" xanh
y như nhau khi resize *không hề xảy ra*, nên mỗi check phải khẳng định luôn là vật đã
đổi kích thước. Mutation test chứng minh điều đó là cần: mutation "làm resize hỏng hẳn"
kéo **cả 5** check "không lưu" sang đỏ — không có positive control thì cả 5 vẫn xanh và
cụm test này chỉ đang chứng minh một no-op là no-op.

Có một check bắt theo *hành vi* chứ không theo hai chỗ đã biết: stub `DimFavorites.add`
rồi khẳng định nó **không hề được gọi** trên đường resize. Thêm một đường lưu mới ở bất
cứ đâu cũng bị nó bắt.

Mutation: 3 cái, 3 đỏ.

**HtmlDialog là một cái browser** — và nó hành xử đúng như browser ở hai chỗ không ai
muốn. Ctrl+A bôi xanh cả trang: tiêu đề, nút, cả danh sách. Chuột phải mở menu của
Chromium: Back, Forward, Print, **View page source**, DevTools. Cả hai đều bị huỷ bằng
`preventDefault`, **trừ trong ô nhập** — ở đó Ctrl+A là chọn cái vừa gõ và chuột phải là
cách dán một dãy `45, 200, 400` vào, cả hai đều đáng giữ. `user-select: none` một mình
không đủ cho Ctrl+A: nó chỉ làm vùng chọn vô hình, phím vẫn coi như đã xử lý.

Hai listener đó giờ chứa **cùng một dòng** `tag === 'INPUT'`, nên `html.include?(...)` sẽ
xanh nhờ listener kia dù chính nó bị xoá. `dim_add_dialog_test.rb` có helper `listener(html,
event)` cắt lấy thân của listener được gọi tên rồi mới đọc trong đó — mutation test xác nhận
là cần: không có helper thì xoá miễn trừ INPUT khỏi `keydown` vẫn xanh hết.

**Cửa sổ không báo lại khi thành công**, theo yêu cầu 2026-08-13. Trước đó có ba dòng ở
dải `#msg`: `Added 1`, `Removed 100`, `Deleted all` — mỗi dòng nói lại đúng cái danh sách
ngay bên dưới vừa thể hiện (thêm một hàng, mất một hàng, rỗng sau khi đã bấm Yes xác nhận).
**Chỉ giữ lại thông báo lỗi** `Cannot read: … -- nothing added`: đó là trường hợp duy nhất
danh sách *không* nói được gì, vì nhập sai thì nó trông y như cũ. Bỏ hết thì một cái typo
được trả lời bằng im lặng.

Kèm theo: `#msg:empty { display: none; }` và bỏ `min-height`. Dải đó giờ gần như luôn rỗng,
mà một thẻ còn `min-height` cộng `margin` thì vẫn chiếm ~28px trống giữa ô nhập và danh
sách. `render()` cũng không còn chọn class nữa — mọi message tới được đó đều là lỗi.
`dim_add_dialog_test.rb` chốt cả ba đường im lặng trong **một** check, vì message quay lại ở
đường nào cũng là cùng một lỗi; mutation test: 5 mutation, mỗi cái đỏ đúng một check.

**Retarget và số đo khi hover — ĐÃ BỎ, cố ý, không phải chưa làm.** Người dùng chốt phạm vi
nhánh này đúng bằng bốn thứ: bỏ pet toolbar, click số đo nhập lại, list kích thước, khoá
trục xyz cho selection nhiều vật (+ phím tắt). Hai tính năng ngoài danh sách đó bị cắt.

| đã bỏ | nó là gì | vì sao nó tốn nhiều hơn vẻ ngoài |
|---|---|---|
| **Retarget** | đang scale vật A, click sang vật B là scale B luôn; click chỗ trống là bỏ chọn | `GRIP_MARGIN`, `outside_grips?`, `own_click?`, `wants_push?`, `pick_object`, `retarget` — và nó là **lý do tool chiếm stack ở mọi nơi ngoài nhãn**, tức nguồn của chuỗi báo lỗi "nháy điểm", "grip inactive", "icon chuột" |
| **Số đo khi hover** | rê chuột qua vật là hiện kích thước vật đó, không cần chọn | `update_hover`, `hover_pick`, `hover_target?`, `build_hover_dims`, `refresh_hover`, `clear_hover`, `draw_hover_bounds/dims/grips`, nút thứ 7, preference `hover_dim` |

Cả hai **không có một dấu vết nào** trong bản gốc Scale++ 1.1.2 (`cd9395b`): 5 method của
retarget và 4 định danh của hover đều đếm ra 0. Nên bỏ chúng là quay về đúng hình dạng gốc,
không phải cắt vào thứ Curic từng có.

Muốn xem lại chúng: nhánh **`scale-full`** (`2389ea0`) giữ nguyên trạng thái đầy đủ, kèm
`hover_dims_test.rb` (47 check), `retarget_test.rb` và `dev/htu_hover_probe.rb`.

Ba thứ **giữ lại** vì chúng không phải retarget/hover mà là sửa lỗi hoặc thuộc bản gốc:
grip thay thế (`draw_scale_points` có trong bản gốc), Text size Small/Medium/Large (bản gốc
có, chỉ sửa lỗi bị ghi đè mỗi lần khởi động), và grip sống qua orbit/pan.

**Con trỏ — plugin KHÔNG chạm vào, cố ý.** Icon Scale (mũi tên kèm ô vuông có góc đỏ) là của
SketchUp và nó **giữ nguyên**: người dùng nhìn nó để biết Scale++ đang bật.

Nó từng bị thay bằng mũi tên trơn theo yêu cầu, rồi người dùng đổi ý xin hiện lại
("cho hiện trở lại miễn scale++ đang bật"). Đã xoá cả hai nửa. Gate `navigation_test.rb`
mục "the cursor stays SketchUp's" chốt là plugin **không đặt con trỏ ở đâu cả** — đáng có
gate chứ không chỉ comment, vì bản đã xoá gồm **hai** call ở **hai** file, vô tình dựng lại
một nửa rất dễ. Mục đó có cả positive control (`UI.set_cursor` phải được shim ghi lại), vì
mọi check còn lại đều assert danh sách **rỗng** — thứ mà một shim ngừng ghi cũng cho ra.

Giữ lại kiến thức, vì tìm ra nó mất công và dựng lại chỉ là việc mười dòng:

1. `ScalePPTool#onSetCursor`. SketchUp hỏi tool ở **đỉnh stack** về con trỏ; **không trả lời
   thì nó giữ con trỏ đặt lần cuối**, tức icon Scale. Đó chính là cách giữ icon hiện nay:
   im lặng. Trả lời là mất icon.
2. `Overlay#onMouseMove` gọi `UI.set_cursor` trực tiếp. **Đây là chỗ tôi ban đầu kết luận
   sai là "không làm được".** Lý do làm được: overlay nhận mouse move **bất kể tool nào đang
   chạy** (§3), và `UI.set_cursor` là **lệnh global**, không phải thứ chỉ callback mới được
   gọi — nên với tới được cả frame mà Scale tool **gốc** đang cầm chuột, tức cả trong vùng
   grip, chỗ `onSetCursor` không tới được.

Nếu có ngày cần lại: gọi **trước** dedupe `@mouse == [x, y]` (chuột không dịch nhưng native
tool vẫn có thể vừa vẽ lại con trỏ), và bỏ qua hai ca — tool khác Scale (con trỏ
Select/Move/Rotate không phải việc của plugin) và suốt lúc camera di chuyển (orbit/pan có
con trỏ riêng mang nghĩa riêng). Ai thắng do SketchUp quyết: native tool trả lời **sau** thì
người ghi sau thắng. Con trỏ chỉ đo được bằng cách nhìn.

**Khoá trục** — 6 lệnh, đều nằm trong menu `Plugins > HTU_ScalePlus`. Đặt
`no_scale_mask` cho definition: all=0, xyz=120, x=126, y=125, z=123. Chế độ là
**preference của máy**, `apply_behavior` áp nó vào mọi thứ được chọn sau đó — nên nó
sống qua component, qua file, qua phiên. Nút không bao giờ bị xám, tick bám theo chế
độ đã nhớ. Bấm lại nút đang bật = tắt về all.

Trên **toolbar chỉ có 4 nút**: bật/tắt overlay, `Scale All`, `Scale XYZ`, số đo —
`main.rb#toolbar_cmds` quyết định, không phải `#cmds`. Ba nút x/y/z riêng bị bỏ khỏi
toolbar theo yêu cầu ("chỉ giữ các icon khoanh đỏ"): tám hình khối gần giống nhau
xếp một hàng thì không phân biệt được bằng mắt. **Chúng vẫn ở trong menu** — đó là chỗ
duy nhất `Preferences > Shortcuts` tìm thấy lệnh, mà phím tắt mới là điểm của ba lệnh
đó. Muốn trả nút về: đổi `toolbar_cmds` trong `main.rb`, không sửa `loader.rb`.
`runtime_test.rb` khoá cả hai chiều — thiếu một trong 4 nút là đỏ, và x/y/z **quay lại**
toolbar cũng đỏ.

**Bắt Scale tool đọc lại mask** — `PLUGIN.repick_scale_tool`. Đây là **một lỗi đã sửa**,
và nó trả lời câu hỏi treo ở §8: `send_action("selectScaleTool:")` **không đủ**.

SketchUp không đọc lại `no_scale_mask` khi Scale tool vẫn là tool đang chạy, và
`send_action("selectScaleTool:")` gọi lên chính tool đang chạy là **no-op**. Nên mask vừa
ghi không được nhìn tới: **bấm nút khoá trục lần đầu không ăn**, phải bấm nút khác rồi quay
lại mới ăn — vì cú bấm thứ hai tình cờ rơi vào lúc tool khác đang giữ stack, khiến cú
re-pick thành một tool change thật.

Đi ra `select_tool(nil)` rồi vào lại là tool change thật, mọi lần. Hai chỗ không được phép
sai — `apply_dim_value` và `dims.rb` — **vốn đã làm đúng như vậy từ đầu**; `set_behavior` là
chỗ duy nhất làm khác. `GroupLock#wrap` giờ cũng gọi hàm này (comment cũ ở đó viết "re-pick
là cách main.rb#set_behavior đã dùng" — hoá ra cách đó mới là cách hỏng).

Cú đi ra đó là tool change dưới mắt observer, nên `GroupLock.suspend { ... }` bọc quanh
`select_tool(nil)`: unwrap ở đây sẽ explode đúng cái wrapper người dùng đang scale và tốn
hai undo step cho một cú bấm nút. **Chỉ nửa "đi ra" được miễn** — Scale tool quay lại vẫn
wrap, và `wrappable?` từ chối wrapper thứ hai khi đã có một cái sống, nên vòng đi-về để lại
đúng cái nó tìm thấy. Rời tool thật thì vẫn unwrap như cũ (có test).

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

**Bộ grip thay thế phải ĐÚNG SỐ LƯỢNG** — đây từng được ghi ngay ở đây như "giới hạn, có từ
trước, không phải hồi quy mới": thứ vẽ là 6 grip mặt do `bounds_center_lines` sinh ra, còn
khi không khoá trục thì SketchUp hiện đủ 26. Nó không phải chuyện thẩm mỹ. Con trỏ băng qua
`GRIP_MARGIN` liên tục trong lúc tiến về phía vật, **mỗi lần băng qua là 26 grip đổi thành
6** — người dùng báo là *"rê chuột lại gần đối tượng đang scale thì nháy điểm"*.

`compute_bounds_for` **vốn đã** tính sẵn đúng bộ theo mask, chỉ là `draw_scale_points` không
dùng. Đo được:

| behavior | SketchUp vẽ | plugin vẽ (trước) | plugin vẽ (giờ) |
|---|---|---|---|
| all (mặc định) | 26 | **6** | 26 |
| xyz | 6 | 6 | 6 |
| x / y / z | 2 | 2 | 2 |

26 = 8 góc + 12 trung điểm cạnh + 6 tâm mặt, tức `bb_data[:scale_points]`. Đường kẻ đứt của
trục cũng cùng câu hỏi: SketchUp vẽ một đường dọc trục đang khoá và **không vẽ gì** khi không
khoá, nên 3 đường lúc không khoá cũng nháy ở đúng cái mép đó. `axis_locked?` tách hai ca mà
`mask_lines` gộp (0 và 120 đều giữ cả 3 line, nhưng 0 cho 26 grip còn 120 cho 6).

`draw_grip_boxes` nhận thêm `loose_points`: điểm chỉ có khối vuông, không có đường trục.
Khoá `[point]` một phần tử, và vòng vẽ bỏ qua `GL_LINES` khi `line.length < 2` — đưa OpenGL
nửa đoạn thẳng thì nó vẽ ra thứ không ai đoán được.

Gate: `grips_test.rb` (tách ra khi bỏ retarget — grip có trước tính năng đó và sống lâu hơn
nó), 5 check đọc số từ
`bb_data[:scale_points]` **và** từ số khối vẽ ra, nên lệch một bên là đỏ. Fixture cũ đưa tool
một `BoundingBox` **rỗng** và `bb_data` chỉ có `:points`, tức mọi check ở đó đang đo nhánh
fallback chứ không phải code chạy thật — đã đổi sang selection thật + `store_bounds_points`.

**Grip thay thế** — `draw_scale_points` vẽ **toàn bộ hoặc không gì cả**, theo đúng một
điều kiện: `active_itself? || navigating?`, tức "SketchUp đang không vẽ grip thật". Lúc đó
mới vẽ, và vẽ đầy đủ: tô ruột `GRIP_FILL = [0,255,0]` (đo từ grip thật) rồi viền xám lên
trên. Lúc SketchUp đang vẽ grip thật thì **không vẽ gì**.

Trước đây viền xám được vẽ **luôn luôn**, với lý luận "viền nằm chồng lên grip xanh thật,
màu xanh lộ ra ở giữa". Lý luận đó sai với selection **phẳng**: SketchUp cho một bộ grip
khác với 6 vị trí `bounds_center_lines` sinh ra — nó gộp cặp trên trục mỏng và bỏ phần còn
lại — nên 4 viền xám bị bỏ lại ở chỗ **không có grip nào**, kèm một grip xanh ở giữa. Người
dùng báo là *"chọn XYZ thì grip các trục bị inactive"*. Không mất gì khi im lặng: grip thật
của SketchUp luôn đúng về việc grip nào tồn tại, còn bản copy này thì không.

Chỉ còn **một** đường vẽ grip. Trước đây có hai: đường này, và grip xám không tô của vật
đang hover. Đường thứ hai đi cùng tính năng hover, xem §4.

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
| `HTU ScalePlus` | `show_dim` | true/false — số đo của vật đang **chọn** |
| ~~`HTU ScalePlus`~~ | ~~`hover_dim`~~ | không còn đọc/ghi — tính năng đã bỏ, xem §4. Giá trị cũ có thể còn trong registry của người dùng, vô hại |
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

Chạy `ruby -c` cho toàn bộ 49 file, rồi 15 gate nữa. Fail bất kỳ gate nào là **không**
đóng gói. Ra `dist/htu_scaleplus-1.2.2.rbz` (**56 file**, ~473 KB).

**Hai gate thêm 2026-08-13, cho lần đem lên store:**

- **`ruby -w`** trên các file **thật sự ship** (không tính `test/` — warning ở đó không
  phải vấn đề của ai). Bắt được 6 chỗ, 4 trong `radial_menu/` là code không hề được
  nạp. Chỉ là warning lúc parse: biến gán mà không đọc, tên bị che. **Không** thấy được
  warning do chính SketchUp phát ra lúc chạy.
- **Bố cục archive**: gốc `.rbz` phải đúng bằng `htu_scaleplus.rb` + `htu_scaleplus/`.
  `lib/` (3 file) và `resources/` (1 file `.gitkeep`) đã **nằm ở gốc suốt 4 version** —
  4 mục ở gốc trong khi chỉ được 2. Không file nào trong plugin require tới chúng. Vẫn
  giữ trong repo, chỉ không vào archive (`EXCLUDE_DIRS` trong `build.rb`).

Cả hai gate đã được mutation test: trả `h = {}` về là build **abort**; bỏ `lib resources`
khỏi `EXCLUDE_DIRS` là build **abort** kèm in ra 4 mục gốc. Gate in chữ xanh mà không
chặn được gì thì tệ hơn không có gate.

Version nằm **một chỗ duy nhất**: `PLUGIN_VERSION` trong `htu_scaleplus.rb` (hiện
**1.2.2**). `build.rb` đọc nó bằng regex để đặt tên .rbz, nên đổi ở đó là đủ — không có
bản sao nào khác trong code. Banner đầu `loader.rb` từng ghi số version và đã bỏ đi
chính vì thế: một bản sao trong comment là một bản sao sẽ lệch.

Con số `1.1.2` còn lại trong `README_BUILD.md` và HANDOFF §1 là **version của Curic
Scale++ gốc** — thứ bản này được dựng lại từ đó — không phải version của plugin này,
đừng sửa theo.

| Gate | File |
|---|---|
| dropped-param scan | `test/dropped_param_scan.rb` |
| load | `test/load_test.rb` |
| runtime | `test/runtime_test.rb` |
| dim favorites | `test/dim_favorites_test.rb` |
| dim menu | `test/dim_menu_test.rb` |
| dim edit | `test/dim_edit_test.rb` |
| add dialog | `test/dim_add_dialog_test.rb` |
| grips | `test/grips_test.rb` |
| behavior | `test/behavior_test.rb` |
| group lock | `test/group_lock_test.rb` |
| navigation | `test/navigation_test.rb` |
| text size | `test/text_size_persistence_test.rb` |
| reload tool | `test/reload_tool_test.rb` — dev tooling, xem §7 |

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
- `Geom::BoundingBox` từng nuốt mọi điểm và trả về 0 cho tất cả — **tám góc đều là gốc
  toạ độ**. Mọi vector cạnh thành invalid, `compute_dimensions_lines` trả list rỗng, nên
  một test có thể chạy hết đường số đo mà không assert được gì: không có số đo nào được
  sinh ra. Nay là box thật (`add` nhận point / array / box / số rời, `corner(i)` đúng thứ
  tự SketchUp: 0→1 là cạnh x, 0→2 là y, 0→4 là z)
- `Geom.linear_combination` từng trả gốc toạ độ. `Utils#midpoint` **chỉ là** hàm này, nên
  mọi trung điểm của mọi khung bao đều nằm ở gốc — đúng chỗ grip được vẽ
- `Geom.point_in_polygon_2D` từng **không tồn tại** → chỗ nào chạm tới là NoMethodError.
  Nó là cách plugin biết con trỏ đang nằm trên chữ số đo, tức toàn bộ cơ chế hover cũ
- `Geom.tesselate` từng **không tồn tại** → `text_geometry` raise, bị `rescue` nuốt, trả
  nil: mọi số đo ra không có chữ, và test không phân biệt được với số đo chưa từng tính
- `Model#axes` từng **không tồn tại** → `snap_text_normal_to_model_axes` chết ngay giữa
  `parse_dimemsion_geometry`, cũng bị rescue nuốt
- `Geom::Transformation` từng là stub **trả lời mọi câu bằng chính nó**: `scaling` bỏ qua
  tham số, `#*` trả `self`, `to_a` trả mười sáu số 0, `Point3d#transform` trả clone. Hệ
  quả: **mọi thứ liên quan tới KÍCH THƯỚC đều ra giống nhau bất kể plugin làm gì**, nên cả
  đường resize — đúng mục đích của nhãn số đo — vô hình với test. `dim_edit_test.rb` chỉ
  kiểm được cái máy trạng thái đằng trước nó, và nó chỉ kiểm đúng thế. Nay là ma trận 4×4
  thật (column-major đúng thứ tự `to_a` của SketchUp), `scaling` có cả dạng quanh một điểm,
  `#*` nhân ma trận, `#inverse` **raise** nếu bị hỏi về ma trận có quay thay vì trả một ma
  trận nghe có lý
- `Entities#transform_entities` từng ghi `<< true` → resize một selection nhiều vật không
  phân biệt được với resize bằng 0. Nay ghi `[transformation, entities]`
- `Camera` từng là bốn reader hằng số, cố định mọi test ở một góc 3/4. Nhãn số đo nằm ở đâu,
  và **nhãn thứ ba có tồn tại hay không**, do camera quyết định — nên góc nhìn từ trên
  không diễn tả được, tức không test được. Nay có `set(eye, target, up)`
- `DCObservers` từng **không tồn tại** → `dc_redraw` raise NameError **ở giữa phép resize**,
  bị rescue quanh nó nuốt, và resize trông như không làm gì cả. Nay có và rỗng: `ObjectSpace`
  không tìm thấy observer nào nên `dc_redraw` return sớm — đúng như SketchUp tắt DC
- `ComponentDefinition` từng **không có `instances`**, entity không có `parent`, và
  `InstancePath` là stub không có `transformation`. Ba thứ đó là toàn bộ đường đi của
  `Referenced Dimensions`: `Utils#get_path` chết ở `i.parent`, và nếu qua được thì mọi
  instance đo ra **cùng một kích thước** vì transform bị bỏ. Nay definition tự vào
  `model.definitions` lúc tạo, `Entities` nhớ `owner` để entity trả `parent` được, và
  `InstancePath#transformation` nhân dồn theo path.
  Một cái bẫy ở đây: back-link phải làm ở **cả hai phía**. Lúc đầu chỉ `definition` (reader)
  gọi `add_instance`, nên một test gán definition dùng chung rồi không đọc lại thì
  `instances` vẫn rỗng — hai instance mà đi qua chỉ thấy một. Cả reader lẫn writer đều
  đăng ký, và mutation test có riêng một mục cho chuyện đó.
  **`Referenced Dimensions` đã bị xoá (§4) nhưng ba thứ này GIỮ LẠI.** Một shim đúng
  hơn không phải chi phí, và fixture `two_instances` vẫn cần chúng: các check "khối đó
  không hiện" chỉ có giá trị khi chạy trên đúng model từng sinh ra nó

Nguyên tắc: nếu một lỗi thật lọt qua được shim, sửa shim trước, rồi mới viết test.

Bốn gạch đầu dòng cuối cùng cùng một chuyện: shim **rescue-được** thì code hỏng vẫn
xanh. Cách phát hiện là viết một check "positive control" — kiểu "the shim itself can measure
a box, or nothing below means anything", hoặc "the shim would notice a cursor being set, or
this proves nothing" trong `navigation_test.rb` — rồi
**mutation test**: sửa hỏng code thật một chỗ, chạy gate, xem có đúng một check đỏ. Đã
làm với 3 chỗ (loại vật đang chọn, cache theo pixel, guard navigation), mỗi lần đúng một
check đỏ.

---

## 7. Vòng lặp phát triển

`dev/htu_scaleplus_reload.rb` đã được đặt sẵn trong Plugins. Trong Ruby Console:

```ruby
HTU_ScalePlusReload.run
```

Nó tự cập nhật chính nó từ repo trước (xem dưới), rồi copy file từ
`E:/htu_scaleplus/htu_scaleplus` đè lên bản đang cài, bỏ tool đang chạy, `load` lại các
sub-file **đúng thứ tự loader.rb**, dựng lại overlay, in MD5.

Vì sao phải copy trước: SketchUp đang chạy **bản đã cài**, reload bản trong repo là
cách kinh điển để đuổi theo một lỗi đã sửa rồi.

Cần khởi động lại SketchUp khi: đổi `loader.rb` phần dựng menu/toolbar, hoặc đổi
`htu_scaleplus.rb`. **Thêm file mới thì không cần** — xem ngay dưới.

### Danh sách file đọc từ loader.rb, không chép tay

Reloader từng giữ `SUB_FILES` chép tay. `group_lock.rb` được thêm vào plugin và **không
được thêm vào danh sách đó**, nên suốt một ngày sửa code:

- `HTU_ScalePlusReload.run` in `== reloaded ==` và 11 dòng MD5 vui vẻ, không một chữ về
  file thứ 12 nó bỏ qua;
- file trên đĩa mới (diff với repo rỗng), nhưng trong bộ nhớ `GroupLock` vẫn là bản
  SketchUp nạp lúc boot — `Sketchup.require` bỏ qua nó vì đã có trong `$LOADED_FEATURES`;
- `PLUGIN.repick_scale_tool` chết ở `GroupLock.suspend`, `rescue` nuốt, **khoá trục im lặng
  không ăn**, và cuộc truy tìm chạy vào plugin — nơi không có gì sai.

Triệu chứng người dùng thấy: chọn trục xong grip đổi theo con trỏ. Ra ngoài khung, plugin
vẽ grip thay thế **có** tôn trọng mask (1/3 trục, nhìn đúng); vào trong khung, SketchUp vẽ
grip thật từ mask **cũ** (đủ trục, nhìn sai). Hai bộ khác nhau, không phải một bộ nhấp nháy.

Hai chỗ đã sửa, và cả hai đều cần thiết:

| | trước | giờ |
|---|---|---|
| danh sách file | `SUB_FILES` chép tay | `sub_files` **đọc `Sketchup.require` từ loader.rb**; `FALLBACK_FILES` chỉ dùng khi không đọc được |
| chính reloader | không bao giờ được sync | `sync_self` copy từ repo, `load __FILE__`, gọi lại `run(true)` |

Cái thứ hai là lý do cái thứ nhất sống sót được lâu thế: mỗi lần chạy nó copy file plugin
rất chăm chỉ và để nguyên đúng cái file quyết định **những file nào** được copy.

Dòng in ra giờ nói thẳng, không để so hai chuỗi hex bằng mắt:

```
thu tu: 12 file tu loader.rb
  8FA48450  scale_tool.rb  <- KHAC repo!
```

Gate: `test/reload_tool_test.rb` (19 check). Nó tự parse `loader.rb` bằng regex **riêng**,
không dùng lại của reloader — một cách đọc so với chính nó thì sai thế nào cũng pass. Có
kiểm cả `FALLBACK_FILES`, vì fallback chỉ được dùng đúng lúc không ai để ý.

**Không** thêm `GroupLock.respond_to?(:suspend)` để `repick_scale_tool` đỡ chết. Fallback
kiểu đó làm bản nạp cũ trở lại vô hình — đúng cái bug này. `p(e)` trong rescue là thứ duy
nhất để lại dấu vết, và nó chính là cái phá án; giữ nguyên.

Một cái bẫy Windows gặp khi viết gate: `File.write` ở chế độ text đổi mọi LF thành CRLF,
bản "copy y nguyên" phình từ 8785 lên 9020 byte và MD5 không bao giờ khớp. `FileUtils.cp`
là binary, nên test phải dùng `binread`/`binwrite`.

Đường dẫn bản cài:
`%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\htu_scaleplus\`

Probe (`prepend`, sống qua reload):

```ruby
load "E:/htu_scaleplus/dev/htu_nav_probe.rb"     # orbit/pan/zoom: grip, viền, đếm draw
```

`dev/htu_hover_probe.rb` đã **xoá cùng tính năng hover**. Nó có một chiêu đáng nhớ, và nếu
cần lại thì lấy ở nhánh `scale-full`: nó **override `p`** trên `ScalePPTool`. Plugin nuốt lỗi
bằng `p(e)`, in ra đúng một dòng `#<NoMethodError: ...>` — không method, không số dòng, không
biết từ rescue nào trong cả chục cái. `p` là private method của Kernel gọi trên chính tool,
nên một module prepend chiếm được nó và in kèm backtrace. Mọi rescue trong `ScalePPTool` —
kể cả trong `draw` — đi qua đó. Dùng lại chiêu này cho bất kỳ lỗi nào chỉ hiện ra dưới dạng
một dòng `#<...>` trong Ruby Console.

Probe đó cũng từng có `.grips` (mask từng vật, trục suy biến, `mask_lines giu N/3`), `.dims`
(nhãn nào thiếu và vì sao) và `.dc` (công thức Dynamic Component nào vỡ). Cả ba vẫn hữu ích
cho phần khoá trục — ở `scale-full`, không phải viết lại.

---

## 8. Việc còn treo

**Ba nhánh, ba mốc lùi khác nhau:**

| nhánh | ở đâu | là gì |
|---|---|---|
| `original-curic-scale-pp-1.1.2` | `523a22d`, **root commit riêng, không parent** | Curic Scale++ 1.1.2 **y nguyên bản ship**, 157 file từ `curic_scale++.rbz` (md5 `1f11ebe7…`). Cài được, **đọc không được**: cả 29 file `.rb` là payload RubyEncoder v3.0.1 nạp qua `rgloader/`. Source đọc được ở các nhánh khác là đã giải mã từ đây |
| `main` | `cd9395b` | source đã giải mã, đổi tên HTU ScalePlus, bỏ license check — **chưa có custom chức năng nào**. Đây là mốc lùi để *đọc và làm lại*, khác với mốc trên là để *cài lại* |
| `scale-group-lock-and-navigation` | **nhánh làm việc** | Phạm vi đã chốt: **đúng 4 chức năng** — bỏ pet toolbar, click số đo nhập lại, list kích thước, khoá trục xyz nhiều vật (+ phím tắt). Retarget và hover dimensions đã cắt |
| `scale-full` | `2389ea0` | Trạng thái **đầy đủ** trước khi cắt: có retarget, hover dimensions, `hover_dims_test.rb`, `retarget_test.rb`, `dev/htu_hover_probe.rb`. Giữ để lấy lại code, không phải để ship |

Đóng gói lại bản gốc mà không cần checkout:

```
git archive --format=zip -o curic_scale_pp-1.1.2.rbz original-curic-scale-pp-1.1.2
```

Nhánh gốc **không có parent** là cố ý: nó không phái sinh từ gì trong repo này, vì chính
`cd9395b` đã là bản giải mã + đổi tên. Diff vẫn được:
`git diff original-curic-scale-pp-1.1.2 main`.

**Chưa push.** `main` vẫn ở `cd9395b`. Remote là
`origin https://github.com/Stark8498/htu_scale.git` — **chưa push, cố ý**: đẩy lên repo
public là việc ra ngoài, để người dùng quyết. `dist/` nằm trong `.gitignore` (nửa MB
binary tái tạo được bằng `ruby build.rb`). Version đã lên **1.2**.

Handoff riêng của đợt 2026-08-12 — báo lỗi nào dẫn tới sửa gì, cái gì chưa kiểm trong
SketchUp thật — ở [HANDOFF-2026-08-12.md](HANDOFF-2026-08-12.md). Đọc nó cùng với §4: một
phần việc trong đó (hover dimensions) đã bị cắt sau khi phạm vi được chốt lại, còn phần sửa
lỗi thì giữ.

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

Đo, đừng suy luận. Chuyện này đã sai **năm** lần vì suy luận: giả định "mọi navigation đều
mất grip" (chỉ orbit đúng), tưởng SketchUp không vẽ overlay (nó vẫn vẽ), tin
`CameraPanTool` là tên thật (là `CameraDollyTool`), tưởng "mất" nghĩa là mất grip (còn mất
**viền vàng** nữa, đó mới là thứ sót lại sau cùng), và — lần thứ năm, ở phần hover
dimensions — tự quyết rằng nhãn không click được thì phải vẽ mờ đi cho khác (video tham
chiếu vẽ đầy đủ, bản mờ đọc ra như tính năng khác).

Cách đo hành vi mong muốn từ một video, nhanh và đủ kết luận:

```
ffmpeg -ss 0.7 -t 1.6 -i cap.mp4 -vf "fps=10,crop=1500:900:1100:700,scale=460:276,tile=3x5" sheet.png
```

`tile` là mấu chốt — một ảnh contact sheet 15 frame nói được cả một chuyển động, thay vì
mở 15 ảnh. Ba thứ đọc được từ đó mà xem video chạy không thấy: nhãn hiện/mất trong **1
frame** khi con trỏ băng qua mép vật (nhanh hơn mọi cú click), **status bar** nói selection
rỗng, và crop-zoom 4K cho thấy grip là khối **xám rỗng** chứ không tô.

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

**`GroupLock` chưa chạy thử trong SketchUp thật.** 16 gate xanh trên shim, nhưng ba điều
chỉ SketchUp trả lời được: (1) group tạm mask 120 có thật sự ra đúng 6 grip khi trước đó
đang chọn nhiều vật hay không; (2) **đã có câu trả lời, xem `repick_scale_tool` ở §4:**
`send_action("selectScaleTool:")` một mình **không đủ**; (3) chuỗi undo sau khi scale xong trông thế nào —
`sweep` là lưới an toàn cho việc đó, nhưng số lần bấm Ctrl+Z người dùng phải chịu thì
chưa ai đếm. Chạy `HTU_ScalePlusReload.run` rồi chọn 2 group, bật nút XYZ, bấm S.

**Rác còn trong .rbz** — `radial_menu/` (18 file) và `radial_menu.rb`, không file nào
được require. **Còn `lib/` và `resources/` đã ra khỏi archive** từ 2026-08-13: chúng
nằm ở *gốc* archive nên vi phạm luật "một `.rb` + một folder cùng tên", chứ không chỉ
là rác — xem §6. `radial_menu/` nằm *bên trong* `htu_scaleplus/` nên không vi phạm bố
cục, và 4 warning của nó đã sửa tại chỗ thay vì xoá file, vì người dùng đã từng chọn
giữ lại. Muốn gói nhẹ hơn thì thêm vào `EXCLUDE_DIRS`, nhưng chưa ai xác nhận
`dims.rb`/`ui/` có gián tiếp đụng tới không.

**`utils.rb:238`** vẫn là `@text_typeface.draw2d_text(view, point, text.to_s, {nil => options})`.
**Mục này trước đây ghi sai hai chỗ, đã kiểm lại 2026-08-13:**
- Không phải `TypeError` vì key `nil`. `TextTypeface#draw2d_text` (`main.rb:442`) nhận
  **3 tham số**, chỗ này truyền **4** → `ArgumentError: wrong number of arguments`.
- Không phải rủi ro sống. Nó nằm trong `draw_dim_text`, chỉ được gọi từ `draw_dim`
  (`utils.rb:257`), mà **`draw_dim` không có caller nào trong toàn plugin**. Cả chuỗi
  là code chết — đó là lý do người dùng chưa bao giờ gặp. Số đo trên màn hình do
  `scale_tool.rb:829` vẽ, đường khác hẳn.

Vẫn để nguyên: sửa một đường không ai gọi tới là đoán xem bản gốc định làm gì. Cùng
chính sách với `listbox.rb` và `definition_paths`.

**`overlay.rb:70`** — `fit_to_length = false` là công tắc tắt cứng, cả khối dưới nó
là code chết. Chưa rõ nó từng làm gì.

**`Utils#definition_paths` / `#get_path`** — từ 2026-08-13 không còn ai gọi:
`referenced_dims` là caller duy nhất và đã xoá cùng `Referenced Dimensions` (§4). Để
lại vì đó là utility của bản gốc, cùng chính sách với `listbox.rb`. Đáng chú ý:
`utils.rb` có **hai bản trùng nhau** của cặp này (dòng ~82/90 trong một module, ~330/338
trong module kia) — chuyện của bản gốc, không phải do lần xoá này.

**`dims.rb` / `DimsUI`** — dialog Vue cũ, vẫn nạp và `observer.rb` vẫn gọi
`DimsUI.dialog`. Từ 2026-08-13 **không còn lối vào nào**: `Show Manager` là mục cuối
cùng mở nó và đã bỏ theo yêu cầu (§4). Ứng viên xoá rõ ràng nhất trong repo — 11 file
`ui/` cộng `dims.rb` — nhưng chưa xoá: `load_test.rb` còn gate
`DimsUI.show_dialog`, `scale_tool.rb:72` còn gọi `DimsUI.toggle_active`, và xoá đúng
thì phải lần cả ba chỗ. Không gấp: code chết không chạy thì không hỏng gì.

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
