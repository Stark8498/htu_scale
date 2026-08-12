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
| `main.rb` | Chế độ khoá trục (`behavior_state` / `set_behavior` / `apply_behavior`), 7 `UI::Command`, `Typeface` |
| `group_lock.rb` | `GroupLock` — nhánh khoá trục cho selection **nhiều vật**: nhóm tạm, mask, dọn |
| `tool.rb` | Lớp cha `Tool`, 18 dòng |
| `dim_favorites.rb` | Danh sách kích thước đã lưu — **chủ sở hữu duy nhất** của phần lưu trữ |
| `dim_menu.rb` | Menu chuột phải trên một số đo |
| `dim_add_dialog.rb` | Cửa sổ `Dimensions` (HtmlDialog, HTML nhúng thẳng trong file) |
| `scale_tool.rb` | `ScalePPTool` — trái tim của plugin, 1370 dòng |
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
45 / 200 / 400      <- tick khi trùng kích thước hiện tại
--------
Open list...        <- mở cửa sổ Dimensions: thêm, xoá từng cái, xoá hết
Text size >         Small / Medium / Large
```

**Một danh sách chung cho cả ba trục**. Trục vẫn được truyền xuyên suốt vì chọn một
kích thước thì phải áp vào đúng trục vừa bấm — chỉ chỗ *lưu* là chung.

**Retarget** — đang scale vật A, click sang vật B là scale B luôn, click chỗ trống là
bỏ chọn. `pick_object` chỉ nhận group/component chưa khoá.

**Con trỏ** — icon Scale (mũi tên kèm ô vuông có góc đỏ) là **của SketchUp**; plugin trước
đây không có một dòng code cursor nào. Bỏ nó cần **hai** chỗ, và chỗ thứ hai mới là chỗ ăn
tiền:

1. `ScalePPTool#onSetCursor` → `UI.set_cursor(PLAIN_CURSOR)`. SketchUp hỏi tool ở **đỉnh
   stack** về con trỏ; không trả lời thì nó giữ con trỏ đặt lần cuối, tức icon Scale. Nhưng
   cái này chỉ với tới được lúc tool giữ stack.
2. `ScalePP2Overlay#set_plain_cursor`, gọi từ `onMouseMove` / `onMouseEnter`. **Đây là chỗ
   tôi ban đầu kết luận sai là "không làm được".** Lý do làm được: overlay nhận mouse move
   **bất kể tool nào đang chạy** (đúng cơ chế nền ở §3), và `UI.set_cursor` là **lệnh
   global**, không phải thứ chỉ callback mới được gọi. Nên ghi đè được cả những frame mà
   Scale tool **gốc** đang cầm chuột — tức cả trong vùng grip.

Gọi **trước** cả dedupe `@mouse == [x, y]` trong `onMouseMove`: chuột không dịch nhưng
native tool vẫn có thể vừa vẽ lại con trỏ của nó. Không đụng vào: tool khác Scale (con trỏ
Select/Move/Rotate không phải việc của plugin) và suốt lúc camera di chuyển (orbit/pan có
con trỏ riêng mang nghĩa riêng).

Ai thắng thì do SketchUp quyết: nếu native tool trả lời câu hỏi con trỏ **sau** khi cái này
chạy thì người ghi sau thắng và cái này thua. Con trỏ chỉ đo được bằng cách nhìn. Nếu id 0
ra hình lạ thì `PLAIN_CURSOR` là một con số duy nhất cần sửa.

**Số đo của vật đang trỏ tới (hover)** — đang bật Scale, rê chuột qua một vật là hiện
kích thước của **vật đó**, không cần chọn. Nút `Toggle hover dimensions` (icon
`snapping_length.png`), preference `hover_dim`, mặc định **bật**.

Ba luật chi phối toàn bộ phần này:

1. **Nhãn hover là read-only, và đó là thiết kế chứ không phải thiếu tính năng.**
   `on_hover?` quét `@data_dims` và nó là thứ quyết định tool có chiếm stack không —
   chiếm stack thì grip gốc tắt. Nhãn hover nằm ở `@hover_dims`, **mảng riêng**, ngoài
   mọi đường quyết định click. Nhét chúng vào `@data_dims` là mất grip mỗi lần con trỏ
   quét ngang một vật. Test `hover_dims_test.rb` chốt đúng chỗ này.
2. **Vật đang trỏ được đo bằng đúng code đo vật đang chọn** — `compute_bounds_for` +
   `compute_dimensions_lines(view, bb_data)` + `build_dim_data(view, dims, bb_data, opts)`.
   Trước kia cả ba viết theo ivar `@bb` / `@bb_points` / `@tr_bb`; đã tham số hoá bằng
   `bb_data`. **Không** được "tạm swap ivar rồi trả lại": `draw` chạy trên đúng những
   ivar đó mỗi frame và sẽ vẽ sai khung suốt thời gian swap. Có test so hai đường đo:
   hover vật X phải ra đúng số mà chọn X sẽ ra.
3. **Đo là đắt, pick là rẻ.** `text_geometry` tessellate từng glyph, nên chỉ đo lại khi
   *vật dưới con trỏ đổi* (`update_hover`) hoặc *camera đổi* (`refresh_hover`, gọi từ
   `draw` vì camera đổi mà không có mouse event nào báo). Cùng một vật, rê bao nhiêu
   pixel cũng không đo lại.

Không đo: chỗ trống, vật đang được chọn (đã có số đo màu của riêng nó — hai nhãn trên một
cạnh chỉ đánh nhau), group tạm của `GroupLock` (nó là scratch, sắp bị explode), lúc đang
kéo grip (`@tool_state != 0`), lúc đang gõ số vào một trục đã khoá, và **suốt lúc camera
đang di chuyển**.

**`hover_pick` đo NHIỀU hơn `pick_object` cho phép click** — hai câu hỏi khác nhau, đừng
gộp lại:

| | `pick_object` (click / retarget) | `hover_pick` (nhãn) |
|---|---|---|
| group / component | nhận | nhận |
| `Face` rời | **từ chối** | **nhận** |
| `Edge` rời, chỗ trống, vật bị lock | từ chối | từ chối |

Lý do nhận `Face`: model thật có những chi tiết vẽ bằng geometry thô nằm thẳng trong
`model.entities`, và đó đúng là chỗ đọc kích thước bằng con trỏ có ích nhất. Đo một mặt thì
vô hại; còn **click** vào nó mà thành vật đang scale thì không phải việc của cú click, nên
`pick_object` giữ nguyên. Có test chốt đúng sự khác biệt này.

Một `Face` phẳng ra **2 số đo**, không phải 3 — nó không có chiều thứ ba để mà đo.
`all_connected` sẽ tìm ra chiều thứ ba, nhưng trên geometry hàn liền với thứ xung quanh nó
sẽ báo kích thước của **cả khối hàn liền đó**, tệ hơn là thiếu một số. Đây là lựa chọn của
người dùng khi được hỏi, không phải mặc định tôi tự đặt. Kèm theo: `draw_hover_grips` bỏ
đường tâm dài 0 (trục mà mặt không có bề dày), nếu không thì hai khối grip nằm đè lên nhau.

Cách tìm ra chuyện này đáng ghi lại: báo lỗi ban đầu là *"hover mặt gần không có số đo, mặt
xa mới có"*. Sai hoàn toàn — probe in ra

```
raw: count=1 best=Face#41632 defn=NO -- bi bo qua
raw: parent=Sketchup::Model
```

tức mặt "gần" là `Face` rời còn mấy vật "xa" là `Group:__38`, `Group:__39`. Gần/xa chỉ là
trùng hợp: hai loại đối tượng khác nhau ở hai khoảng cách khác nhau. Hai màn hình chụp
không thể phân biệt được điều đó.

Về navigation: hover bị **xoá** khi `navigating?`, không phải đo lại từng frame. Pick đã
lỗi thời ngay frame đầu của cú kéo, và `Overlay#navigation_finished` replay lại vị trí
chuột ngay khi nhả nút nên nhãn tự về. `clear_hover` xoá luôn `@hover_mouse` — nó là
guard "cùng vật, khỏi làm gì", để lại thì nhãn không về cho tới khi người dùng vẫy chuột.

Vẽ: **giống hệt** số đo của vật đang chọn — cùng màu theo trục (đỏ/xanh lá/xanh dương),
cùng nền trắng, cùng đường gióng, cùng 6 khối lập phương xám và đường tâm nét chấm. Một
đường vẽ duy nhất: `draw_dimension(view, dim, editable)`, `editable = false` chỉ tắt ba
thứ (editor tại chỗ, caret, viền đánh dấu nhãn đang hover/đang khoá).

**Đây là chỗ tôi đã tự quyết sai một lần, ghi lại để không ai làm lại.** Bản đầu vẽ nhãn
hover xám phẳng, chỉ 2D, không đường gióng, với lý luận "nhãn không click được thì không
nên trông giống nhãn click được". Đo lại trên video tham chiếu
(`bandicam 2026-08-09 22-02-46-420.mp4`, tách 10 fps): hành vi được yêu cầu vẽ vật đang
trỏ **đầy đủ**, và bản xám đọc ra như một tính năng khác, kém hơn. Ba check trong
`hover_dims_test.rb` chốt lại phần nhìn này. Lần thứ năm suy luận về mặt nhìn ở plugin này
thua đo — xem §9.

**Không vẽ khung bao**, và đây cũng là đo được: khi selection rỗng, **Scale tool của
SketchUp tự vẽ khung xanh quanh vật dưới con trỏ** (pre-highlight). Bằng chứng: suốt cả
đoạn hover trong video, status bar giữ nguyên *"Click the item or object you want to
scale"* — tức không có gì được chọn, nên khung xanh đậm đó là của SketchUp. Vẽ thêm khung
nữa chỉ là đè lên khung nó đang vẽ.

Grip của vật đang trỏ **không bao giờ tô xanh lá** (`GRIP_FILL`). Tô là cách plugin đóng
thế cho grip thật đã ngừng được vẽ; vật đang trỏ thì SketchUp vẫn đang vẽ grip thật của
nó, tô vào là vừa đè lên vừa nói dối rằng nó là vật đang scale. Mask lọc theo
`mask_lines(lines, entity)` với entity là **vật đang trỏ**, không phải selection.

`draw` gọi phần hover **trên** guard `@dims` (số đo của *selection*), vì `@dims` rỗng khi
chưa chọn gì — mà đó đúng là lúc hover có ích nhất: bấm S rồi trỏ.

**Hai lỗi đã sửa, cả hai đều làm nhãn hover biến mất và cả hai đều không phải lỗi của
riêng phần hover:**

1. `deactivate` bị SketchUp gọi cho **hai việc khác nhau**: người dùng rời Scale tool, và
   tool bị pop khỏi stack sau khi nó tự push (xảy ra liên tục, mỗi lần con trỏ về vùng
   grip thì `call_back` pop). `clear_hover` nằm chung một chỗ nên nhãn bị xoá **ngay trong
   cùng mouse event vừa tính ra nó**. Phân biệt bằng `@on_push_tool`.
2. `@dims` **sống lâu hơn** `@bb`: `deactivate` gọi `store_bounds_points` với selection
   rỗng (→ `@bb = nil`) nhưng **không** tính lại `@dims`. Frame sau đi qua được guard
   `@dims` rồi đưa một box nil cho `bound_points`, hỏi `#width` của nil. `draw` rescue và
   `p(e)` in ra — nên triệu chứng là **Ruby Console đầy `undefined method 'width' for
   nil:NilClass` theo tốc độ frame**, và mọi thứ dưới chỗ raise ngừng được vẽ. Guard nằm
   trong `draw_selected_bounds` và `draw_scale_points` (chỗ test tới được), không phải
   trong `draw`.

Đường sự kiện: `update_hover` được gọi từ **cả hai** chỗ — `ScalePPTool#onMouseMove` và
`Overlay#dispatch_mouse`. Không chỗ nào đủ một mình: khi tool nằm trên stack thì SketchUp
tự gọi `onMouseMove` (overlay không được gọi lại, sẽ nhân đôi mọi event), khi tool ở ngoài
stack thì chỉ overlay có event. Gọi hai lần vô hại vì `update_hover` return ngay khi chuột
chưa đổi toạ độ.

**Khoá trục** — 6 nút trên toolbar và trong menu `Plugins > HTU_ScalePlus`. Đặt
`no_scale_mask` cho definition: all=0, xyz=120, x=126, y=125, z=123. Chế độ là
**preference của máy**, `apply_behavior` áp nó vào mọi thứ được chọn sau đó — nên nó
sống qua component, qua file, qua phiên. Nút không bao giờ bị xám, tick bám theo chế
độ đã nhớ. Bấm lại nút đang bật = tắt về all.

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

**Giới hạn, có từ trước:** thứ tô là 6 grip mặt do `bounds_center_lines` sinh ra. Đang khoá
trục thì đúng bằng những gì SketchUp hiện. Không khoá thì tool gốc hiện đủ 27 và 21 cái còn
lại vắng mặt suốt lúc di chuyển camera — đúng bản copy thiếu mà chỗ này vẫn vẽ mỗi khi giữ
stack, không phải hồi quy mới.

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

Grip của vật đang **hover** vẫn vẽ viền xám không tô — khác đường, khác lý do, xem §4.

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
| `HTU ScalePlus` | `hover_dim` | true/false — số đo của vật đang **trỏ tới**, default true |
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

Chạy `ruby -c` cho toàn bộ 49 file, rồi 13 gate. Fail bất kỳ gate nào là **không**
đóng gói. Ra `dist/htu_scaleplus-1.2.rbz` (62 file, ~493 KB).

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
| hover dims | `test/hover_dims_test.rb` |
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

Nguyên tắc: nếu một lỗi thật lọt qua được shim, sửa shim trước, rồi mới viết test.

Bốn gạch đầu dòng cuối cùng cùng một chuyện: shim **rescue-được** thì code hỏng vẫn
xanh. Cách phát hiện là viết một check "positive control" — `hover_dims_test.rb` mở đầu
bằng "the shim itself can measure a box, or nothing below means anything" — rồi
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

Hai probe, cùng một khuôn (`prepend`, sống qua reload):

```ruby
load "E:/htu_scaleplus/dev/htu_nav_probe.rb"     # orbit/pan/zoom: grip, viền, đếm draw
load "E:/htu_scaleplus/dev/htu_hover_probe.rb"   # hover: LÝ DO không có nhãn
```

`htu_hover_probe` có một thứ đáng nhớ ngoài phần hover: nó **override `p`** trên
`ScalePPTool`. Plugin nuốt lỗi bằng `p(e)`, in ra đúng một dòng `#<NoMethodError: ...>`
không có method, không có số dòng, không biết từ rescue nào trong cả chục cái. `p` là
private method của Kernel gọi trên chính tool, nên module prepend chiếm được nó và in kèm
backtrace. Mọi rescue trong `ScalePPTool` — kể cả trong `draw` — đi qua đó. Dùng lại chiêu
này cho bất kỳ lỗi nào chỉ hiện ra dưới dạng một dòng `#<...>` trong Ruby Console.

`HTU_HoverProbe.stats` trả lời câu "không in dòng nào nghĩa là gì": đường hover **chưa hề
chạy** (tool không active nên không ai gọi vào), khác hẳn với chạy rồi nhưng quyết định
giống nhau mọi lần (chỉ in một dòng).

`HTU_HoverProbe.grips` in cả chuỗi quyết định về grip trong một lần: `behavior_state`, mask
của từng vật đang chọn (hoặc "KHONG co definition"), độ dài từng trục kèm cờ suy biến,
`mask_lines giu N/3`, có đang vẽ grip thay thế hay không. Nó là cái phủ định giả thuyết
"geometry thô" của tôi trong hai dòng (`mask=125`, `giu 1/3 truc`) và đẩy vụ án sang
reloader. Dùng nó trước khi sửa bất cứ gì về grip.

**Trước khi nghi plugin, kiểm bản đang nạp.** Lỗi nào có mùi "code đúng mà chạy sai" thì
đọc dòng MD5 của `run` và tìm chữ `KHAC repo!` trước tiên. Cả một ngày đã mất vì bỏ qua
bước đó.

---

## 8. Việc còn treo

**Đã commit, chưa push.** Branch `scale-group-lock-and-navigation`, 5 commit trên
`cd9395b`, kết thúc ở `f754d83`. `main` vẫn ở `cd9395b`. Remote là
`origin https://github.com/Stark8498/htu_scale.git` — **chưa push, cố ý**: đẩy lên repo
public là việc ra ngoài, để người dùng quyết. `dist/` nằm trong `.gitignore` (nửa MB
binary tái tạo được bằng `ruby build.rb`). Version đã lên **1.2**.

Phần hover dimensions (§4) làm sau 5 commit đó và **chưa commit**.

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

**Hover dimensions chưa chạy thử trong SketchUp thật.** 35 check xanh trên shim, nhưng
hai điều chỉ SketchUp trả lời được, và cả hai đều là thứ shim *không thể* trả lời:

1. **Giá thật của việc đo.** Shim không tessellate glyph thật (`Geom.tesselate` là fan
   đơn giản, `Transformation#transform` là identity). Trong SU thật, mỗi lần đổi vật dưới
   con trỏ là ba nhãn được dựng lại từ đầu. Cache đã chốt bằng test (cùng vật, rê bao
   nhiêu pixel cũng không đo lại), nhưng "rê nhanh qua 20 group trong một model nặng" thì
   chưa ai đo. Nếu thấy giật: nơi cần đo là `build_hover_dims`, và cách rẻ nhất là
   debounce bằng `UI.start_timer` chứ không phải bỏ cache.
2. **Có bị lẫn với số đo của vật đang chọn không.** Đã tách bằng màu xám phẳng, chỉ 2D,
   không extension line — nhưng đó là suy luận về mặt nhìn, và §9 cho thấy suy luận về mặt
   nhìn ở plugin này sai bốn lần. Cách đo: video capture, xem mục ffmpeg ở trên.

Giới hạn đã biết, cố ý: chỉ group/component top-level và `Face` rời được đo — không đo
`Edge` (một số đo không đáng cái nhãn), và một mặt phẳng ra 2 số chứ không phải 3. Xem bảng
`hover_pick` vs `pick_object` ở §4.

**`GroupLock` chưa chạy thử trong SketchUp thật.** 13 gate xanh trên shim, nhưng ba điều
chỉ SketchUp trả lời được: (1) group tạm mask 120 có thật sự ra đúng 6 grip khi trước đó
đang chọn nhiều vật hay không; (2) **đã có câu trả lời, xem `repick_scale_tool` ở §4:**
`send_action("selectScaleTool:")` một mình **không đủ**; (3) chuỗi undo sau khi scale xong trông thế nào —
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
