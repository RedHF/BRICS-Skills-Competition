# 回响版美术资产与生成记录

## temple_hall_master.png

- 日期：2026-11-02；图像生成工具：Codex 内置 image_gen；采用参考编辑，未使用 CLI 回退。
- 用途：回响版正殿母图。原始 temple_incense.jpeg 保留；原版仍使用原图，回响版目录单独引用本文件。
- 实际原生尺寸：1672×941，RGB。不将其描述成原生 1920×1080。未来正式展示采用真实 1920×1080 实机渲染截图，并分别说明运行图与展示图的尺寸。
- SHA256：a7b42e3753aad1a3d6b5656a2850f906d32088c29ba38a4e6d8c173a583577d4。
- 输入 1（编辑对象）：assets/landscape/temple_incense.jpeg。
- 输入 2（风格参考）：仓库 material/Example2.jpg。
原始生成路径在工作档案留存，本副本省略个人路径。
- 采用依据：保留原俯视室内构图、主梁、柱、门、供桌与香炉；去除大面积蓝绿偏色，改为灰黑旧木与米灰墙面；提高梁端与墙面细节可读性。
- 当前边界：这是母图色调与可读性修订，不是已完成的构件修复动画或三种状态图。交互热点与图层将基于本图实际位置继续制作。

### 最终提示词

Use case: precise-object-edit. Asset type: production environment master for the existing Chinese heritage game 檐下千秋. Image 1 is the EDIT TARGET, the existing temple hall interior, and image 2 is a STYLE REFERENCE ONLY for the warm paper and neutral ink palette. Preserve image 1's camera angle, perspective, room proportions, columns, giant horizontal foreground beam, carved brackets, side doorway, wooden table, incense vessels and ground layout exactly. Make a sibling refined version of this same location, not a redesigned temple. Primary changes: remove the pervasive teal, cyan and deep green cast from the walls, shadows and floor; use neutral charcoal ink, faded warm-gray plaster, weathered dark brown and muted red timber, beige stone and soft ivory daylight. Keep the beautiful existing detailed painterly ink realism and aged architecture, matching the existing game's materials. Gently lift muddy shadow midtones so the beam ends and joinery are readable, while keeping natural depth and a solemn old-building atmosphere. Retain old plaster wear, cracks and timber grain. No new characters, new furniture, labels, interface panels or calligraphy. Do not add a green or teal palette. Do not make the room a simplistic flat vector drawing or a brand-new clean temple. Landscape 16:9 composition, preserve the complete source framing.

## empty_bowl.png

- 日期：2026-11-03；Codex 内置 image_gen，未使用 CLI 回退。工具未返回可核实的底层模型名称，不补写猜测。
- 编辑参考：assets/landscape/temple_guest.jpeg，提取同类旧陶碗的材质、俯视角度与旧化程度。
- 原生尺寸：1536×1024，RGBA；透明通道范围 0—254，保留工具生成的透明边缘与柔和接地影。
- SHA256：6fbe6df9718ae21a2cb2645f66a2364cc99eff3684f6c5f8243fe5d19a4f993c。
原始生成路径在工作档案留存，本副本省略个人路径。
- 运行用途：可移动空碗及重访时同一实体。显示宽为场景图宽的 10.5%，高宽比 62:92，地面锚点相当于 92×62 框内的 (46,48)；预览跟随场景缩放，候选托盘稍放大。实际落点按场景归一化坐标保存。
- 采用理由：朴素旧陶、磨白碗沿、碗内空；未新增食物。需继续结合实机检查尺度、接地和透明影边缘。

### 最终提示词

Use case: precise-object-edit / background-extraction. Asset type: single draggable game object, transparent PNG. Reference image is the existing temple side-room scene in 檐下千秋. Create ONE empty small old ceramic rice bowl matching the existing rice bowl near the lower-right of the source: humble dark weathered brown pottery, warm gray/beige worn rim, matte handmade ceramic, subtle age, no food, no decoration, no lettering. Isolate the whole bowl including its complete rim and base with a genuinely transparent background. Camera looks down at the bowl at the same oblique angle as the source scene, so its inside is visible and its base can rest on that scene's floor. Match the existing game's detailed painterly Chinese ink and restrained realistic textures. No green or teal tint, no glowing magic, no UI, no surrounding floor, no checkerboard painted into pixels. Center the single bowl with a small clear margin; no extra bowl and no collage.

## drum_face.png

- 日期：2026-11-03；Codex 内置 image_gen，未使用 CLI 回退；底层模型名称未由工具明确返回。
- 输入 1：assets/landscape/temple_drum.jpeg，作为同一鼓的对象与纹样参考。输入 2：assets/rubbings/she_hui_chun.png，仅作墨纸质感参考。
- 原生尺寸：1254×1254，RGB；没有宣称原生 2K。
- SHA256：7ca63b00c45df07ad55238c93256e15aad7933f228e9dabd4de210182adb8c57。
原始生成路径在工作档案留存，本副本省略个人路径。
- 采用理由：外环、中央纹与横向旧修补线均能辨认；米灰旧鼓皮、残墨和旧木边沿与原材料接近。纹理在引擎中通过动态遮罩显出，不把用户鼠标线当作新的文物图纹。
- 当前边界：这是近景交互纹理，前坪远景仍使用原图；不将近景当作远景修复动画已经完成的证据。

### 最终提示词

Use case: precise-object-edit. Asset type: close-up square interaction texture for the same ceremonial drum in the existing Chinese heritage game 檐下千秋. Image 1 is the original temple courtyard scene and is the identity reference for the actual drum; image 2 is the game's existing collectible print and is a supporting ink/paper material reference only. Produce a straight-on near-orthographic top view of ONE complete round drum face filling most of a square canvas, including a narrow dark aged wooden rim. Preserve the original drum's worn hide and recognizable circular old decorative pattern; use the established warm ivory hide, faded charcoal ink, ochre old wood and tiny muted vermilion traces. Make three readable motif zones: an outer circular ornament band, a modest central circular motif, and one thin visibly old stitched repair line running roughly horizontally through the middle. The line is an existing repair trace, not a fresh wound. Retain gentle irregular wear; do not make a shiny new instrument. The face should be readable as a physical drum close-up with slightly tactile hide and flat-enough lighting for gradual digital rubbing reveal. Minimal neutral warm paper outside the circular rim. No text, captions, UI, hands, human characters, tools, extra drums, new building, teal or green color grade. Match the existing detailed painterly ink game artwork, not a flat vector icon.

## 运行效果与声音

- 构件轮廓及匹配槽口由引擎确定绘制，木纹采样自原 tenon_piece.png 的完整木面。左右朝向和缺角不是生成模型猜出的答案。原素材不变。
- 脚步暖迹、空碗暖影和鼓边跟拍微光是独立记忆图层。梁上捐木记号是实体旧痕，归档后仍在。后续已补入抬梁手影原画并接入鲜活回应，归档时仅让手影退出，修好的梁继续保留。
- drum_single.wav（1.4 秒）与 distant_gong.wav（2.6 秒）为程序合成、24000 Hz/单声道/16 位 PCM；可由联调脚本/generate_echo_audio.py 固定种子复现，不是真人演奏录音。
- 童声复用原 voice/temple_drum_dialogue_02.wav，对应已有字幕“一、二、三！”。只有鲜活回春保留时才可在取舍后敲鼓中播放；原版语音资源未改动。
- 初步自动检查只能确认文件可加载、播放开关及状态正确；尚未通过真人扬声器听感检查。

## artisan_standing.png

- 日期：2026-11-03；Codex 内置 image_gen，使用现有封面作身份参考，未使用 CLI 回退；底层模型名称未由工具明确返回。
- 输入：assets/landscape/welcome.png 中左侧的成年拓印师。保留头带、发束、墨黑米白袍服、灰交领、腰带流苏、右手长笔与左手谱册；去除新的可读标题，避免生成错字。
- 原生尺寸：1024×1536，RGBA；透明通道 0—254，双脚和笔尖完整。透明区也有 RGB 底色，应在实际 alpha 合成后判断边缘，而非把 RGB 底色当成不透明背景。
- SHA256：7759634f972b0cc0eac597295ca9ac8ac5c773ed2150424a0c7728e7c14711cb。
原始生成路径在工作档案留存，本副本省略个人路径。
- 初始采用范围为成年站立身份与风格基准板；11 月 3 日后续已配套行走和抬笔关键姿态接入回响版调查、守护和闪身残影。原版仍使用原帧；新表现为三关键姿态加运行位移，不称为十八帧新动画。

### 最终提示词

Use case: identity-preserve / background-extraction. Asset type: a single full-body adult player-character reference for the existing game 檐下千秋, transparent PNG. Image 1 is the strict identity and costume reference: the young adult Chinese male rubbing artisan on the left of the existing cover, with black tied-up long hair and black headband, calm face, charcoal-black outer robe with aged ivory brushlike sections, gray cross collar, simple dark belt and hanging tassel, traditional brush in right hand and the same dark thread-bound booklet in left. Preserve that specific identity, clothing design, accessories, restrained ink illustration medium and neutral charcoal/ivory palette. Extend naturally to a COMPLETE standing full body including both feet and the entire brush, in an easy readable three-quarter view facing slightly to screen right, calm ready-to-work pose. Adult proportions approximately seven heads tall, normal-sized head and hands, grounded feet and coherent limbs. Simplify small face and clothing details enough to read at about 180 pixels tall in a game, while retaining the existing cover's beautiful painterly ink edges, clear robe silhouette and worn textile texture. One character only, centered with clear transparent margin all round; no contact shadow beyond a tiny soft trace under the shoes. The booklet may have a blank small ivory title label; do not generate any legible text. This is a faithful sibling asset for the same character, not a redesign. No background, landscape, UI, lettering, painted checkerboard, green or teal tint, fantasy armor, new weapon, oversized head, chibi style, extra poses, collage or extra character.

## 后续动作与梁架

artisan_walking.png、artisan_casting.png 和 temple_hall_cleanplate.png 的原始输入、实际尺寸、哈希和完整提示词，见 [动作与梁架生成记录](./动作与梁架生成记录.md)。三者均使用内置生图参考编辑，已复制至本项目，不引用生成目录作为运行路径。

正殿梁架使用母图中的原木纹，补图只填梁后局部；引擎控制倾斜、承架、落稳与旧拼缝，不重画全场景。首轮实机发现梁左端遮罩不足，已扩大到真实梁端轮廓并重新渲染。减弱环境动态时直接显示稳定状态，调查与修复判定一致。

## 后续线索与记忆层

三结红绳鼓槌、抬梁手影、侧厢蓑衣与两双筷子的局部修订、旧饭碗清晰近景已生成并接入。均用内置生图，完整提示见 [线索与记忆层生成记录](./线索与记忆层生成记录.md)。鼓槌、手影及饭碗近景均为原生 1536×1024 RGBA，透明范围 0—254；侧厢补图为 1672×941 RGB。运行只使用两块局部补区，其他像素仍绘制原侧厢图。未改动原版本的素材。

| 文件 | SHA256 |
| --- | --- |
| drum_beater_three_knots.png | 803b38aefb66ac7b6a8bd9174379fb8c4f9fc8dfacf3fd3d3499ff95acb98aba |
| beam_lifting_hands.png | 8d652d86e6e9c0a9ad3954a8c5001159d8987e4ab450259f4ccf84924d036dab |
| temple_guest_detail_patch.png | 3391723232250add47965045c29ae75eef90d03be719c3df21c126e9ce9d3250 |
| guest_bowl_close.png | b745ea4d11c02d3357642d8369186d634e2a411a9e6e473cdd1b8aead2eee02e |

近看旧饭碗有米饭与两双筷子；玩家移动的 empty_bowl.png 保持空碗，两件物品不混用。红绳三结是游戏叙事中的数拍线索，不作为历史民俗考证。梁口与木件是游戏化简化，不作为现实古建筑修缮指导。
