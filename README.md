# Numberfactory / 质数工厂

Godot 4.7 / GDScript 二维原型。设备免费，没有限时任务；通过累计交付 12、18、30 推动研究、探索与中央枢纽建设。

## 运行

用 Godot 4.7 打开 `project.godot`，按 F6 运行 `main.tscn` 或按 F5 运行项目。仓库不包含 Godot 引擎和导入缓存，首次打开时由编辑器自动导入素材。

本机若已在 `.tools/portable/` 准备便携版 Godot，也可以双击 `run_game.cmd` 运行；该目录不随仓库上传。

## 操作

- 左键放置或选择；拖动铺设传送带，折线自动转向，空带也会显示弯道。
- 可先放乘法机，再把传送带拖到输入口；也可从输入口向外反向铺带。接到设备后停止延伸。
- 点击已有传送带可调整方向，带上的物料保留。
- 中键拖动地图，滚轮缩放；工具栏的四角图标显示整张地图。
- R 旋转，右键或 Esc 取消建造，1–5 切换工具，空格暂停，Ctrl+S 保存。
- 乘法机后方输入 A，左侧输入 B，自动将实际输入的两个数字相乘，前方输出；无需设置配方。
- 分流器四向可用。相邻传送带朝向分流器时是输入，背离时是输出；允许多路合流和多路均分，连接变化后自动更新。
- 比例分流可选择主输出方向及其权重；数字筛选可为每个输出方向设置全部数字、指定数字或其余数字。指定数字优先匹配，指定出口堵塞时等待，不会绕到错误出口。两项功能仍分别在研究 20、60 时解锁。
- 拖动新传送带穿过已有直带时，原带保留在地面，新路线自动从该格地下直行。两层各有一个物料缓存、带速均为每秒 3 个，独立堵塞，不合流、不换线；连续交叉同样支持。
- 弯道、设备和未开放区域不能地下穿越，交叉格内不能转弯。在选中面板可查看两层物料或单独拆除地下通道；普通拆除清空该格两层。
- 需求设施不接收错误数字。乘法机缺少任一输入时等待，输出堵塞时保留缓存；乘积超过 999999 时保留两份输入并显示警告。拆除会清空缓存物料。

## 永久目标

研究站累计 20 个 12 解锁比例分流，60 个 12 解锁数字筛选。探索站累计 30 个 18 开放新区域与质数 5。中央枢纽累计 60 个 30 完成建设。设施达标后继续接收。

自动保存间隔为 30 秒，关闭窗口时也保存。存档在 Godot 的 `user://number_factory_v1.json`，关闭期间不模拟生产。新建工厂需要确认。

旧版配方存档可直接读取，布局、缓存、加工进度和累计交付保留，后续加工改为自动识别输入。存档内容升级为版本 2，文件名保持不变；旧版分流筛选和空弯道出口会自动迁移，新存档同时保存地下物料和四向筛选。

## 贴图

九种贴图使用内置 GPT 图像生成制作，采用抽象数学实验室风格。完整提示词、透明背景设置与显示尺寸见 `assets/texture_manifest.json`。原始 PNG 保存在 `assets/textures/`，Godot 使用 mipmaps 缩小显示。数字、端口和流向由引擎实时绘制。

弯带使用重绘的 `belt_turn-v2.png`；渲染网格校准入口、出口和轨道宽度，使旋转与镜像后的接缝均对齐。初版弯带原图仍保留。

四向分流器使用内置 GPT 重绘的 `splitter-fourway.png`。地下通道复用原带贴图，用引擎绘制隧道口和物料指示点，地面路线始终显示在上方。

工具栏使用 [Lucide](https://github.com/lucide-icons/lucide) 图标，许可文件位于 `assets/icons/LICENSE`。

## 验证

```powershell
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/simulation_test.gd --log-file qa-simulation.log
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/interface_test.gd --log-file qa-interface.log -- --qa --test
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/belt_build_test.gd --log-file qa-belt-build.log -- --qa --test
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/belt_texture_test.gd --log-file qa-belt-texture.log -- --qa --test
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/routing_test.gd --log-file qa-routing.log -- --qa --test
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x800 --script res://tests/routing_test.gd --log-file qa-routing-1280.log -- --qa --test --visual
& '.\.tools\portable\Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x800 -- --qa --demo --detail
```

测试覆盖物料守恒、满载传输、自适应乘法、超限堵塞、旋转端口、四向分流及筛选优先级、输入/输出公平性、双层独立堵塞、连续交叉、正反向拖建、真实矿点驱动的完整成长循环、存档兼容、界面命令与贴图透明通道。`--qa` 不读取或写入玩家存档，截图写入 `qa/`。

验证用 Godot 来自官方 4.7.2 发行包，保存在忽略的 `.tools/`；游戏逻辑不依赖该目录，可使用现有 Godot 编辑器运行。
