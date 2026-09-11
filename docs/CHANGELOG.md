# Niratan Mac Changelog

This changelog records user-visible changes only. Implementation details, investigation logs, and temporary experiments belong in commits, issues, or focused design docs.

## 1.6.6

### 中文

- Video 的 ASS/SSA 字幕现在支持在统一外观与“尊重 ASS 字幕自带样式”之间切换；两种模式都保留文字选择、查词和制卡，并支持常见的字体、颜色、位置、移动和淡入淡出效果。
- AJATT 与 Jimaku 下载的外挂字幕现在会按视频归档并记住；下次打开同一视频时可以恢复，关闭字幕后也能直接重新启用，不会重复加载字幕轨道。

### English

- Video ASS/SSA subtitles can now switch between the uniform appearance and a Respect ASS Subtitle Styles mode. Both modes keep text selection, lookup, and card mining available while supporting common authored font, color, positioning, movement, and fade effects.
- External subtitles downloaded from AJATT and Jimaku are now archived per video and remembered. They can be restored when the same video is reopened and re-enabled after being hidden without loading duplicate tracks.

## 1.6.5

### 中文

- 视频底部控制栏新增“保存纯净截屏”相机按钮，可截取当前视频画面并保存为 PNG，不包含播放器黑边、控件及外挂字幕。悬浮栏、贴底栏和窄窗口均可使用。
- 默认截图文件名包含视频名称和播放时间。视频画面本身压入的字幕或黑边仍会保留。

### English

- Added a Save Clean Screenshot camera button to the video controls. Capture the current video frame as PNG without player letterboxing, controls, or external subtitles, including in floating, compact-bottom, and narrow layouts.
- Screenshot filenames include the video name and playback time. Subtitles or borders burned into the source video remain in the image.

## 1.6.4

### 中文

- 修复在“音频”设置中删除自定义音频源时应用闪退的问题。

### English

- Fixed a crash when deleting a custom audio source in Audio Settings.

## 1.6.3

### 中文

- 修复原生 Video 字幕调轴区在部分窗口尺寸下裁切偏移数值的问题，`-10000 ms` 等完整数值现在可正常显示。
- 修复 Video 进入或退出全屏时窗口态顶部栏仍然停留、红黄绿窗口按钮显示不全的问题；全屏过渡期间不再残留顶部色带，返回普通窗口后也会正确恢复。

### English

- Fixed subtitle timing offsets being clipped in the native Video inspector at some window sizes; complete values such as `-10000 ms` now remain visible.
- Fixed the windowed titlebar remaining visible and the macOS traffic-light controls being clipped when entering or leaving Video full screen. The top strip no longer remains during the transition, and the normal windowed titlebar restores correctly afterward.

## 1.6.2

### 中文

- 原生 Video 的“外挂字幕”检查器新增原生 AJATT 日语字幕浏览器：可按当前视频自动推测标题和集数，在 App 内搜索动画或真人影视目录、浏览匹配文件，并将选中的 SRT、ASS 或 SSA 直接送入现有字幕显示、列表、查词与制卡流程，无需跳转网页。

### English

- Native Video's External Subtitles inspector now includes a native AJATT Japanese Subtitles browser. It infers the current title and episode, searches anime or live-action catalogs in the App, lists matching files, and routes a selected SRT, ASS, or SSA through the existing overlay, transcript, lookup, and mining path without opening a website.

## 1.6.1

### 中文

- 原生 Video 的字幕检查器新增“获取字幕（Jimaku）”弹窗：采用更宽大的桌面双栏布局，可在同一处配置 API 密钥、按当前视频标题搜索动画或真人影视条目、修改自动推测的集数，并把选中的 SRT、VTT、ASS 或 SSA 直接送入现有字幕显示、列表、查词与制卡流程。弹窗及字幕检查器操作统一使用 macOS 26 Liquid Glass 控件；API 密钥单独保存在 macOS 钥匙串，也可在“视频”设置中修改。
- 漫画新增“发现”页，可在 AniList 与 MyAnimeList（经非官方 Jikan 接口）之间切换，浏览趋势、热门、高分和连载栏目，提交标题搜索并分页查看结果。作品详情会依次尝试已安装的 Aidoku 图源，自动匹配或手动更正漫画后直接查看章节、加入书库并使用现有原生阅读器；数据源选择和作品图源匹配会被记住，成人内容继续跟随现有 Aidoku 开关。
- 原生 Video 的 YouTube 字幕选择现在同时列出发布者字幕与同语言的自动生成字幕，并明确标记自动轨道；选择后会一次性下载并解析完整 WebVTT，再用于画面字幕、字幕列表、查词和制卡，不会随播放实时生成。
- 漫画 Google Lens OCR 现在跟随阅读时捕获的 Profile 语言：英语页面使用英语识别并保留单词与跨行空格，日语页面继续使用日语识别；两种语言的缓存彼此隔离。
- 漫画连续滚动模式现在无缝衔接相邻页面，不再显示页间黑色间隙或页面栈上下留白。
- 修复 Aidoku 图源请求限流可能在整秒边界提前放行的问题，并提高大量并发请求时的稳定性。

### English

- Native Video's subtitle inspector now opens a dedicated Get Subtitles (Jimaku) sheet with a larger desktop two-column layout. The same flow configures the API key, searches anime or live-action entries from the current video title, lets the inferred episode be edited, and routes a selected SRT, VTT, ASS, or SSA through the existing overlay, transcript, lookup, and mining path. The sheet and inspector actions use macOS 26 Liquid Glass controls; the key is stored separately in macOS Keychain and can also be changed in Video Settings.
- Manga now includes Discover with switchable AniList and MyAnimeList metadata (the latter through the unofficial Jikan API), home shelves for trending/popular/top/publishing titles, submitted search, and paged results. Details try installed Aidoku sources serially, then automatically or manually match the title, browse chapters, add it to the library, and open the existing native reader. The discovery provider and per-work Aidoku match are remembered, while adult visibility continues to follow the existing Aidoku setting.
- Native Video now lists publisher captions and same-language auto-generated YouTube captions as separate, clearly labeled choices. Selecting a track downloads and parses the complete WebVTT once for the overlay, transcript, lookup, and mining instead of generating captions incrementally during playback.
- Manga Google Lens OCR now follows the Profile language captured by the reader: English pages use English recognition and preserve word and line spacing, while Japanese pages continue to use Japanese recognition. Caches for the two languages remain isolated.
- Continuous Manga reading now joins adjacent pages seamlessly without black inter-page gaps or vertical padding around the page stack.
- Fixed Aidoku source rate limiting potentially releasing requests early at a whole-second boundary, and improved stability under larger concurrent request batches.

## 1.6.0

### 中文

- 漫画新增原生 Aidoku `.aix` 图源支持，与 Suwayomi 并列提供图源管理、浏览、在线书库、登录、章节进度和原生阅读；远程漫画入口默认选择 Aidoku，并内置 Aidoku Community Sources 列表。图源下载列表支持按名称、ID、别名、列表和语言即时搜索，并显示列表或已安装包提供的图源图标。Aidoku 数据为 App 全局数据，阅读时只捕获当前 Profile 用于词典、Popup 与 Anki；成人内容默认隐藏，HTTP/局域网来源和第三方代码安装均需确认。图源在受限的解释器型 WASM 兼容层中运行，并经过包路径、ABI、内存、超时、响应、缓存和原子更新边界保护；App 不包含官方 AidokuRunner、Shinsou、Java/Mihon APK 或额外 helper。

### English

- Manga now supports native Aidoku `.aix` sources alongside Suwayomi, including source management, browsing, a global online library, login, chapter progress, and the shared native reader. Remote Manga surfaces default to Aidoku and include the Aidoku Community Sources list out of the box. The source download catalog can be searched instantly by name, ID, alias, list, or language and shows icons supplied by the catalog or installed package. Aidoku data is App-global while the reader captures the current Profile only for dictionaries, Popup, and Anki. Adult content is hidden by default, and third-party code plus HTTP/LAN access requires confirmation. Sources run inside a bounded interpreter-only WASM compatibility layer with package, ABI, memory, timeout, response, cache, and atomic-update protections; the App includes no official AidokuRunner, Shinsou, Java/Mihon APK, or extra helper.

## 1.5.8

### 中文

- 统计 Dashboard 的“书籍排行”不再只显示前 12 本；排行底部新增“更多书籍”，每次继续显示 12 本，切换日期范围或排行指标后会从首批重新显示。

### English

- Book Ranking in the Statistics dashboard is no longer capped at the first 12 books. A More Books control reveals 12 additional entries at a time and resets to the first page when the date range or ranking metric changes.

## 1.5.7

### 中文

- 修复视频播放时调整播放器尺寸、进入或退出全屏可能出现严重卡顿的问题；渲染层现在按 IINA 的做法保持稳定 surface，避免逐次布局强制重绘，并防止 mpv 渲染队列长时间阻塞主线程。
- 统计 Dashboard 的“书籍排行”现在显示书籍封面；点击排行项可打开按日统计面板，调整已读字数和阅读时长，或经确认后删除当天及整本统计。面板修改会同步刷新正在打开的 Reader，避免旧的内存统计覆盖手动调整。
- 词典搜索结果顶部现在会以紧凑间距保留原始查询文字；可像 Yomitan 一样在这一行点击任意字符，从该位置向后扫描并选中实际匹配的词，下方现有结果区域会直接改为该词的结果，不再弹出嵌套 Popup。词条自身的大号词头不会因此变成查词区域。
- 阅读统计新增每日重置时间，可精确到分钟；重置时间之前的阅读会计入前一天，Reader 的“今日”统计与书架统计 Dashboard 使用同一日切规则。
- 改进视频播放器的窗口缩放与沉浸观看体验：播放器会以更合适的舒适尺寸居中打开；拖动窗口边缘或角落时，画面会持续、稳定地按视频比例缩放，不再抖动或卡住；基础窗口下限与 IINA 对齐为 285×120，实际最小尺寸继续跟随视频比例，窄窗口会收起次要控制并保留播放与时间轴；底部控制栏自动隐藏或随指针恢复时，顶部标题栏、标题和窗口按钮会同步淡出淡入，隐藏后顶部区域仍可拖动窗口。
- 视频播放器时间轴现在会标出章节起点，便于在较长视频中辨认章节边界；标记只作视觉提示，不会拦截拖动或点击进度条。
- 主窗口工具栏不再强制绘制第二层不透明底色，页面的 Liquid Glass 背景会稳定延伸到标题栏，避免调整窗口大小时顶部区域突然变色。
- Anki 设置现在可以单独调整动画 AVIF 的最大高度与帧率；降低任一项都能在保留 iOS 全关键帧兼容性的同时进一步缩小卡片媒体体积，不同参数生成的图片不会错误复用缓存。

### English

- Fixed severe playback stutter while resizing the player or entering and leaving full screen. The render layer now follows IINA's stable-surface approach, avoids forced redraws on every layout tick, and prevents the mpv render queue from starving the main thread.
- Book Ranking in the Statistics dashboard now shows book covers. Clicking a ranking row opens daily statistics where characters and reading time can be adjusted, or the selected day/all book statistics can be deleted after confirmation. Edits also refresh an open Reader so stale in-memory totals cannot overwrite them.
- Dictionary results now retain the original query in a compact dedicated line at the top. Clicking any character scans forward, selects the actual matched term, and replaces the results below in place instead of opening a nested Popup, Yomitan-style. Entry headwords remain outside lookup.
- Reading statistics now have a minute-level daily reset time. Reading before that boundary counts toward the previous day, and Reader's Today totals use the same reporting day as the Bookshelf Statistics dashboard.
- The Video player now opens centered at a better-tuned comfortable default size, while resizing remains smooth and stable from every edge and corner and preserves the video's aspect ratio. Its 285×120 base minimum matches IINA, with the effective minimum still following the video ratio and narrow windows retaining playback and timeline controls while hiding secondary actions. When the bottom controls auto-hide or return with pointer activity, the titlebar, title, and traffic lights fade with them, while the hidden top region remains available for dragging the window.
- The Video player timeline now marks chapter starts for easier navigation in longer videos. The markers are visual only and do not intercept seeking or timeline clicks.
- The main window toolbar no longer forces a second opaque background. The page's Liquid Glass background now extends consistently into the titlebar, avoiding a top-bar color jump while resizing the window.
- Anki settings can now tune animated AVIF maximum height and frame rate independently. Lowering either reduces card media size while preserving iOS-compatible all-keyframe playback, and media generated with different values never collides in the cache.

## 1.5.6

### 中文

- 修复视频字幕制卡可能在动画 AVIF 尚未写入 Anki 媒体目录时提前提交的问题；重复制卡会等待同一媒体生成完成，截图或音频失败时不再留下缺失文件引用。
- 修复部分视频导出动画 AVIF 时出现黑帧、奇数尺寸失败、旋转方向错误或 HDR 色彩信息丢失的问题，并限制超长字幕动画时长、降低导出内存占用。
- 更新动画 AVIF 缓存版本并把字幕延迟后的实际画面区间纳入文件名，避免继续复用旧编码参数或错误区间的缓存。

### English

- Fixed Video subtitle cards being submitted before animated AVIF and audio media finished writing to Anki. Repeated cards now wait for shared media generation, and failed captures no longer leave missing-file references.
- Fixed animated AVIF black frames, odd-dimension failures, incorrect rotation, and lost HDR color information for affected videos. Long subtitle animations are now bounded and export with lower memory overhead.
- Updated the animated AVIF cache version and included the actual delay-adjusted capture range in filenames so stale encodes and mismatched ranges are regenerated.

## 1.5.5

### 中文

- 修复从视频挖矿历史跳回已选中的内嵌字幕轨道时，交互字幕与转录可能被清空的问题；返回历史记录后字幕查词与制卡上下文会继续保持可用。
- 视频字幕制卡的动画 AVIF 改用更紧凑的画面尺寸与编码参数，减少短字幕片段生成的媒体体积；同时恢复制卡准备、成功与失败提示，字段准备失败时也会明确反馈。

### English

- Fixed interactive subtitles and the transcript potentially being cleared when returning from Video Mining History to an already selected embedded subtitle track. Subtitle lookup and mining context now remain available after history navigation.
- Animated AVIF captures for Video subtitle mining now use a more compact frame size and encoding profile to reduce media size. Card preparation, success, and failure feedback is restored, including clear errors when field preparation fails.

## 1.5.4

### 中文

- Anki 制卡新增图片格式选择，可在 JPEG 和 AVIF 之间切换，并继续支持图片质量调节；设置同时适用于小说封面和视频截图。
- 视频字幕制卡支持按字幕区间生成动画 AVIF 截图，减少连续画面占用的媒体体积；重复使用相同视频片段和图片设置时会复用已有媒体文件。

### English

- Anki card creation now lets you choose JPEG or AVIF for compressed images while retaining adjustable image quality. The setting applies to book covers and video screenshots.
- Video subtitle mining can generate animated AVIF captures for the selected subtitle range, reducing media size for continuous footage and reusing matching media files when the same source range and settings are mined again.

## 1.5.3

### 中文

- 修复 Sasayaki 资源页打开音频或字幕文件时，文件选择器状态可能过早清空导致导入类型丢失的问题；音频和字幕现在都会稳定完成导入，并统一使用原生 Liquid Glass 操作按钮。

### English

- Fixed Sasayaki resource imports losing their selected audio or subtitle type when the file picker state cleared too early. Audio and subtitle imports now complete reliably and use the native Liquid Glass action-button styling.

## 1.5.2

### 中文

- 优化 Sasayaki 资源页的字幕导入：音频与字幕现在由同一个原生文件选择器处理，字幕支持 SRT 及普通文本文件，避免在设置面板中嵌套打开文件选择器。
- 更新 Niratan 原生侧边栏品牌区域，加入新的图标与标题布局，让应用导航更易识别。

### English

- Improved Sasayaki subtitle importing. Audio and subtitle files now use one native file picker, with subtitles accepting SRT and plain-text files instead of presenting a nested picker inside the settings panel.
- Refreshed the native Niratan sidebar branding with a new icon and title layout for clearer app navigation.

## 1.5.1

### 中文

- 漫画新增外部 Suwayomi Server 连接器：可连接本机、局域网或反向代理后的现有服务器，使用无认证、Basic Auth、Suwayomi 界面登录或 Bearer Token，浏览服务器已安装图源的热门/最新、搜索、详情与章节，并使用 Suwayomi 书库和章节进度。浏览与在线书库的海报会复用本地漫画库的固定比例 Liquid Glass 卡片，不再裁成另一套宽封面。在线漫画与本地图书共用现有原生阅读器的单双页、连续阅读、章节切换、缩放、裁边、宽页拆分、OCR、查词和 Anki 图片制卡。Niratan 不再安装或运行 Shinsou 脚本，也不内置 Java、Mihon APK 或另一套阅读器；扩展安装、配置、Cookie 和站点兼容由外部 Suwayomi 负责。
- 修复在线图源中单张图片加载缓慢或失败时整章 OCR 直接停止的问题；图片请求现在允许更长的有界等待并合并同页并发下载，失败页经过重试后保持待处理，后续页面继续识别，下次打开时只重试缺失页面。
- 优化在线漫画打开体验：点击在线书库卡片、阅读按钮或具体章节后会立即打开独立阅读窗口，详情、章节或首页仍在准备时直接在 Reader 内显示加载状态；失败时也留在该窗口提供重试，不再让来源页面长时间无响应。
- 优化在线视频打开体验：从视频库点击 YouTube 条目后会立即进入独立播放器，并在链接解析与媒体加载期间显示转圈状态，不再让视频库停在原处等待。
- 修复快速切换 Profile、Suwayomi Server 或漫画详情时可能混用旧连接、凭据、章节或缓存的问题；远程页面与 OCR 缓存现在按 Profile、服务器和章节版本隔离并限制容量，漫画查词始终使用当前 Profile。
- 修复对同一视频选择“从头播放”仍恢复旧进度的问题；远程视频解析失败或取消不再清空当前播放与字幕，解析后的书库元数据也会在所有窗口保持一致。
- 漫画库的本地/在线、浏览与图源导航以及本地整理操作已移入原生窗口工具栏；普通窗口下整理与导入按钮不再被挤进 `»` 溢出菜单，离开本地页也会结束选择模式，避免对隐藏选择执行移动或移除。Suwayomi 详情页改用原生 Liquid Glass 操作并优化封面布局。

### English

- Manga now includes an external Suwayomi Server connector for local, LAN, or reverse-proxied servers with no authentication, Basic Auth, Suwayomi UI login, or bearer tokens. It browses installed sources, popular/latest lists, search, details and chapters, and uses the server-owned library and reading progress. Browse and online-library posters reuse the local Manga library's fixed-ratio Liquid Glass cards instead of cropping covers into a separate wide treatment. Online titles share the existing native reader's chapter navigation, paged/spread/continuous layouts, zoom, crop/split processing, OCR, lookup, and Anki image mining with local books. Niratan no longer installs or executes Shinsou scripts and does not bundle Java, Mihon APKs, or another reader; extension installation, configuration, cookies, and site compatibility remain Suwayomi's responsibility.
- Fixed whole-chapter OCR stopping when one online-source image loaded slowly or failed. Page requests now receive a longer bounded wait and coalesce concurrent loads for the same page; a repeatedly failing page remains pending while later pages continue, and reopening retries only missing results.
- Improved online manga launch responsiveness. Clicking an online-library card, Read, or a specific chapter now opens the dedicated reader window immediately and shows page preparation inside it while details, chapters, or the first page are still loading; failures remain in that window with Retry instead of leaving the source surface apparently unresponsive.
- Improved online-video launch responsiveness. Clicking a YouTube library item now enters the dedicated player immediately and shows a loading indicator through link resolution and media loading instead of waiting silently in the library.
- Fixed rapid Profile, Suwayomi Server, or manga-detail switches potentially mixing stale connections, credentials, chapters, or caches. Remote page and OCR caches are now isolated by Profile, server, and chapter revision with bounded storage, while manga lookup always follows the active Profile.
- Fixed Play from Beginning on the currently open video restoring its old progress. A failed or cancelled remote-video resolution now preserves the current playback and subtitles, and resolved library metadata remains consistent across windows.
- Manga local/online, browse, and source navigation plus local organization actions now live in the native window toolbar. Organization and import buttons no longer collapse into the `»` overflow menu in a normal window, and leaving the local library ends selection mode so hidden selections cannot be moved or removed. Suwayomi details use native Liquid Glass actions with an improved cover layout.

## 1.5.0

### 中文

- 改进词典与本地音频稳定性：词典索引改在后台构建，切换 Profile 时不会暂时返回上一套词典结果；本地词语音频会优先选择表达式与读音同时匹配的结果。本地媒体端口初始化失败不再导致 App 崩溃，TTU 导出的 EPUB 图片路径及音频来源拖动后的开关/删除也得到修复。
- 新增原生本地漫画库与独立阅读窗口：通过一个“导入漫画”入口按单本选择 Mokuro 文件夹、EPUB 或 Mokuro ZIP/CBZ 压缩包，不再把上级目录挂成递归扫描的漫画来源。Mokuro 压缩包可直接读取包内 `.mokuro`/`mokuro.json`；同一个压缩包包含多份 Mokuro 漫画时会按元数据及子目录拆成多本书，每本拥有独立的标题、封面、页列表和进度，不再把所有图片合并。EPUB 会按 OPF spine 及正文引用图片确定页面顺序，不会把封面资源或装饰图片按压缩包文件名混入正文。按自然顺序浏览并记忆进度，支持单页、按阅读方向排列的双页和连续滚动。阅读布局与阅读方向可直接在一级菜单中勾选，并会在下次打开漫画时恢复上次选择；左右方向键按该阅读方向翻页。双页共用同一个缩放画布，会随窗口或全屏尺寸自适应放大，在完整显示页面的前提下铺满可用宽度或高度，并保持统一倍率、居中与固定中缝。已有 Mokuro 元数据会优先按图片文件名直接提供文字和坐标，打开页面即可悬停查词，不会重复 OCR 或上传；没有 Mokuro 的 EPUB 可在首次说明后启动整本 Google Lens 识别，从当前页扫到末尾再回到第一页，并显示进度和取消入口。每页完成后会立即写入 App 缓存，取消、失败或重启后只续扫缺失页面，重新打开也不会重复上传已完成页面；来源版本或页列表变化时会自动失效，且始终不会改写原 EPUB/Mokuro。悬停任意识别文字会按 Mangatan 的方式在半透明白色行框中浮现整个文本块，点击仍从当前文字开始查词，制卡则直接使用整个文本块作为句子及命中文字所在的完整漫画页。横排 Popup 居中显示在文本块正上或正下，竖排显示在正左或正右，缩放、居中或滚动后仍使用可见文本块的实际位置，靠近边缘时自动翻转，且不会改变小说、视频或词典查词的定位。点击画面空白处或按下 `Esc` 即可退出 Popup，无需额外关闭按钮，也不依赖 WebView。导入项始终只读，刷新或移除书库记录不会改动用户文件；界面使用 macOS 26 原生控件和 Liquid Glass，不使用旧式 Material。
- 漫画导入现在也支持不带 Mokuro 的普通图片文件夹与普通 CBZ/ZIP；每次选择仍只导入一部漫画，图片按自然顺序排列并自动使用首张有效图片作为封面，不会重新启用上级目录递归扫描。压缩包中的 macOS 隐藏资源文件不会混入页列表，没有可读图片的来源会直接提示错误。
- 修复漫画导入面板中 CBZ 文件显示但无法选中的问题。
- 小说与漫画书架现在统一使用 macOS 26 单层 Liquid Glass 卡片和分组管理界面，不再在玻璃组件内叠加旧 Material 或 grouped Form 卡片。管理页外层与 Reader 的 Sasayaki 面板一致，使用顶部标题和右上关闭按钮；添加按钮改为无背景操作，输入框复用 AnkiConnect 的胶囊玻璃样式，“在读书架”改用原生 switch。漫画库提供独立的漫画分组、最近/标题/手动排序、拖拽排序、批量移动或移除、重命名与标记已读；导入项会明确显示在“未归类”，打开后从第一页起同时进入动态“正在阅读”分组。右上角保持简洁，不再显示刷新、来源移除和搜索控件。移除卡片不会删除原漫画文件，重新进入书架不会让它恢复，再次显式导入同一来源即可恢复。
- 修复多卷 Mokuro 文件夹及压缩包识别：同级的 `书名 v01.mokuro` 与 `书名 v01/` 图片目录会准确配对并拆成独立书籍，即使每卷都从 `001.jpg` 开始也不会交叉或合并。
- 修复 App 构建签名或文件授权上下文变化后，已导入的漫画 EPUB 与 Mokuro 压缩包可能无法再次打开的问题；重新选择同一原文件会刷新只读访问授权、清除旧错误并恢复被移除的卡片，同时保留阅读进度和书库元数据。
- 修复进入漫画页面时，异步读取书库前会短暂显示“暂无漫画”导入页面的问题；漫画目录现在由主窗口提前加载并跨侧栏切换保留，只有确认书库确实为空后才显示空状态。
- 修复首次进入或切回小说书架时整排封面会短暂变成灰色占位的问题；首批封面会在卡片出现前完成准备，书架状态也会跨侧栏切换保留并复用已经解码的缩略图。
- 漫画单页与双页阅读现在可在任意缩放比例下使用鼠标滚轮翻页：滚轮输入达到阈值后向下前进、向上后退，并通过 250 毫秒节流避免连续误翻；触控板双指滚动继续平移画布，`⌘/Control + 滚动`会在分页和连续布局中缩放并同步工具栏百分比，连续阅读的无修饰键滚动仍保持原生行为。按住右键拖动可在分页和连续布局中平移画布；连续页会越过 SwiftUI 宿主层解析实际滚动容器。右键单击具体页面可复制图片、另存为 PNG、调用系统分享或将该页设为书架封面，且不会修改漫画源文件。
- 漫画阅读器右上角的页码入口改为紧凑跳页浮层，可直接跳到首页、上一页、输入指定页码、下一页或末页，也可用滑杆快速定位，不再展开与整本页数等长的菜单。
- 漫画阅读器左上角的翻页按钮改为原生胶囊式左右导航组；物理左、右箭头会跟随“从右到左”或“从左到右”的阅读方向切换前进与后退语义。
- 漫画阅读器新增扫描页处理：可自动识别超宽双页并拆成两个独立阅读页，日漫从右半页开始、左到右漫画从左半页开始；也可裁掉连续的扫描白边。拆分和裁边同时适用于单页、双页与连续布局，并同步修正查词坐标，但不会旋转页面或改写原漫画文件。
- 修复 Sasayaki 跨章节跳转回含图片的上一章时可能卡住、落到章节开头并让阅读统计倒退的问题；失败图片不再阻塞 Reader 恢复，程序化跳句不会计入阅读字数，暂停/恢复滚动、跨节点标点高亮、Ruby 空白节点及数字 HTML 字符实体的匹配位置也一并修正。打开非统计面板或全屏图片时会暂停阅读计时。分页阅读还会覆盖出版方嵌套分栏并移除可能扭曲行盒的 WebKit 样式，连续查词的选区高亮更新也更稳定。
- 修复多个目录章节共用同一个 EPUB 页面时，章节列表位置、当前章节标记及“读完本章”时间按整页计算的问题；旧书会在后台安全补齐章节锚点，不会重置书签、图片库或阅读统计。
- 修复 Reader 连续 Shift 悬停及嵌套查词时，新旧查词 WebView 与 macOS 输入法争抢焦点可能导致的闪退；悬停查词现在通过不抢焦点的窗口级按键监听保持响应。

### English

- Improved dictionary and local-audio stability. Dictionary indexes now build in the background without exposing results from the previous Profile during a switch, and local word audio prefers an exact expression-and-reading match. Media-server port failures no longer crash the app, and TTU EPUB image paths plus reordered audio-source toggles/deletion are corrected.
- Added a native local manga library and dedicated reader window with one direct import action for an individual Mokuro folder, EPUB, or Mokuro ZIP/CBZ archive; selecting a parent folder no longer mounts it as a recursively scanned manga source. Mokuro archives can read internal `.mokuro`/`mokuro.json` files, and an archive containing multiple Mokuro books is split by metadata/root into separate titles, covers, page lists, and progress instead of merging every image. EPUB pages follow the OPF spine and each content document's referenced image so unrelated cover assets or decorations are not mixed into reading order. Progress is preserved, and single-page, reading-direction-aware double-page, and continuous layouts are available. Reading layout and direction choices are checked directly in their first-level menus and restore the last selection when another manga opens; Left/Right arrow page turns follow that reading direction. Double-page spreads share one zoom canvas that scales up with the window to fill the available width or height while keeping pages fully visible, centered, and separated by a fixed gutter. Existing Mokuro metadata supplies text plus geometry by image filename, so hover lookup works immediately without repeated OCR or upload. EPUB without Mokuro can start whole-manga Google Lens recognition after the first-use disclosure; scanning begins at the current page, wraps to the beginning, and exposes progress plus cancellation. Each completed page is stored immediately in the app cache, so cancellation, failure, relaunch, or reopening resumes only missing pages without re-uploading completed ones; source-version or page-list changes invalidate those results without ever modifying the EPUB or Mokuro source. Following Mangatan, hovering any recognized character reveals its complete text block as scaled black text on translucent white line rectangles; lookup still begins at that character, mining uses the complete block directly as the sentence, and the card picture is the hit manga page rather than its library cover. The same lookup path now works in continuous layout, where each lazy page loads Mokuro or cached OCR regions at its fitted size and whole-manga recognition can remain enabled while scrolling. Horizontal Popup placement is centered above or below the block, vertical placement is centered left or right, and the visible block remains the anchor after zooming, centering or scrolling; edges flip the side automatically without changing Reader, Video or Dictionary lookup placement. Clicking blank space or pressing `Esc` closes the Popup without a separate close button or WebView. Imports stay read-only when refreshing or removing library records, and the UI uses macOS 26 native controls and Liquid Glass without legacy Material.
- Manga import now also accepts ordinary image folders and ordinary CBZ/ZIP archives without Mokuro. Each selection remains one non-recursive manga, pages use natural ordering, the first valid image becomes its cached cover, macOS hidden resource entries are excluded from archives, and sources without readable images report an error instead of adding an empty title.
- Fixed CBZ files appearing disabled in the Manga import panel.
- Novel and manga libraries now share macOS 26 single-layer Liquid Glass cards and shelf management without nesting legacy Material or grouped Form cards underneath glass components. The management surface matches Reader's Sasayaki panel with a top title and trailing close action; Add is a background-free action, the text field reuses the AnkiConnect capsule-glass style, and Reading uses the native switch instead of a checkbox. Manga retains independent shelves, recent/title/manual sorting, drag reordering, bulk move/removal, rename, and mark-read actions. Imports are visibly labeled as Unshelved, and opening one adds it to the dynamic Reading section from its first page. The top-right toolbar stays focused by omitting refresh, source-removal, and search controls. Removing a card never deletes the original manga; reopening the library keeps it hidden, and explicitly importing the same source restores it.
- Fixed multi-volume Mokuro folder and archive detection. Sibling pairs such as `Book v01.mokuro` and `Book v01/` are matched and indexed as separate books, so volumes that each start at `001.jpg` no longer cross-match or merge.
- Fixed imported manga EPUB and Mokuro archives potentially becoming inaccessible after the app's signing or file-authorization context changes. Explicitly selecting the same source now refreshes its read-only access, clears the stale error, and restores removed cards while preserving progress and library metadata.
- Fixed the Manga section briefly showing the “No Manga” import screen before its asynchronous catalog snapshot arrived. The main window now preloads and retains the manga catalog across sidebar switches, and only presents the empty state after confirming the library is actually empty.
- Fixed the novel Bookshelf briefly showing an entire grid of gray cover placeholders on first entry or when returning from another sidebar section. Its first cover batch is prepared before cards appear, while retained catalog state and decoded-thumbnail reuse keep later transitions ready on the first frame.
- Manga reading now provides persistent 50%–200% page zoom across single-page, double-page, and continuous layouts through a macOS 26 Liquid Glass popover with a page-navigator-width slider and exact percentage field. Slider movement updates its percentage immediately but applies the expensive page relayout only when dragging ends, keeping continuous manga adjustment responsive. Page-number and zoom inputs share the same native glass treatment, and the redundant zoom preset menu has been removed. Paged zoom remains centered in the native pan/zoom canvas, while enlarged continuous pages support horizontal and vertical scrolling without detaching OCR lookup regions.
- Single-page and double-page manga reading now support mouse-wheel page turns at every zoom level: thresholded wheel-down advances and wheel-up goes back, with a 250 ms cooldown preventing repeated accidental turns. Precise two-finger trackpad scrolling continues to pan the canvas, while Command/Control-scroll zooms and synchronizes the toolbar percentage in both paged and continuous layouts; unmodified continuous scrolling remains native. Holding and dragging the secondary mouse button pans both paged and continuous canvases, with continuous pages resolving the real scroll container through SwiftUI's hosting hierarchy. A secondary click on a page offers native copy, full-resolution PNG save, system share, and Set as Manga Cover actions without modifying source media.
- The manga reader's top-right page control is now a compact navigation popover with first, previous, validated page input, next, last, and slider controls instead of a menu as long as the entire book.
- The manga reader's top-left page buttons now use one native capsule navigation group, with physical left and right arrows switching forward/back behavior to match the selected right-to-left or left-to-right reading direction.
- Manga reading now includes scan-page processing. It can detect wide two-page scans and expose each half as a separate reading page—right half first for right-to-left manga and left half first for left-to-right comics—and can crop contiguous white scan borders. Splitting and cropping work across single-page, double-page, and continuous layouts with remapped lookup geometry, without rotating pages or rewriting source media.
- Fixed Sasayaki cross-chapter navigation into a previous image-containing chapter potentially stalling, landing at the chapter start, and reducing reading statistics. Failed images no longer block Reader restore, programmatic cue jumps no longer count as reading, and paused/resumed scrolling, cross-node punctuation highlighting, ruby whitespace, and numeric HTML character-reference offsets are aligned. Reading time also pauses behind non-statistics sheets and the full-screen image viewer. Paginated reading now overrides nested publisher columns and removes a WebKit line-box rule that could distort layout, while repeated lookups update a stable active selection highlight.
- Fixed chapter-list positions, current-chapter highlighting, and time-to-finish calculations when multiple TOC chapters share one EPUB page. Existing books backfill chapter anchors safely in the background without resetting bookmarks, gallery metadata, or reading statistics.
- Fixed a possible crash during continuous Shift-hover and nested Reader lookups when lookup WebViews raced the macOS input method for focus. Hover lookup now stays responsive through window-level modifier tracking without stealing focus.

## 1.4.5

### 中文

- Anki 制卡新增 AAC / MP3 音频格式与可调比特率，并将可调质量的图片压缩统一用于小说封面和视频截图；同一句有声书/字幕音频及相同封面会复用已有媒体，连续制作多张卡时不再重复导出或覆盖。

### English

- Anki mining now offers AAC/MP3 audio compression with adjustable bitrate and applies adjustable-quality image compression to both book covers and video screenshots. Repeated cards reuse matching audiobook/subtitle clips and covers instead of exporting or overwriting them again.

## 1.4.4

### 中文

- 书架新增采用 macOS 26 Liquid Glass 样式的 Z-Library 搜索与 EPUB 导入入口，支持账号会话、最近新增、下载历史和今日下载额度。搜索默认日语，支持数字年份、精确匹配、筛选重置和可逐条删除的最近搜索；三个入口会分别记住结果、页码、滚动位置、详情和排序。年份/文件大小排序可在后台获取最多 200 条结果后全局排序，并可随时取消。书籍详情改为原生侧边面板，展示大封面、完整简介、ISBN、出版社、语言、页数、系列、文件与额度信息；展开详情时会为结果区保留完整宽度，简介也可滚动到固定导入栏上方，切换书籍会同步刷新详情数据和封面。结果支持方向键选择、`Space` 查看详情、`Return` 排队导入、`⌘←`/`⌘→` 翻页和 `⌘F` 聚焦搜索。多本书可串行排队，单项取消并汇总成功、重复和失败，下载后继续停留在结果页并立即刷新额度。封面采用内存/磁盘缓存、受限并发和离屏取消，并区分无封面与网络失败；下载历史会在后台刷新服务器已失效的旧封面地址。导入书籍会保存 Z-Library 来源 ID 和 ISBN，以更可靠地识别重复书籍。
- Niratan 现在只提供一个同时包含小说阅读与视频学习的全功能安装包，不再区分 Light / Video 版本。
- 阅读器的图片库、外观、跳转、统计和 Sasayaki 现在使用统一的居中原生面板，并将关闭按钮固定在右上角。
- Sasayaki 面板新增“资源 / 章节 / 设置”分段；资源页整合音频导入与字幕匹配，播放区显示音频封面信息，M4B 内嵌章节可查看并直接跳转。书架右键不再重复显示匹配入口，阅读器“跳转”面板默认打开章节列表。
- 游戏手柄设置现在与键盘快捷键使用相同的完整动作列表和分类；可为全部播放、字幕、音频、循环、Transcript 与全屏动作录制手柄按键，并保留旧有 Reader / Sasayaki 映射。
- Anki 字段映射现在使用合并的可编辑下拉输入框，整项只绘制一层 macOS 26 Liquid Glass，不再在原生玻璃外叠加旧式灰色 material；App 升级后仍会保留自定义及明确清空的字段映射。

### English

- The Bookshelf now includes a macOS 26 Liquid Glass Z-Library search and EPUB import experience with account sessions, recently added books, download history, and visible daily quota. Search defaults to Japanese and supports numeric years, exact matching, filter reset, and individually removable recent queries; each content entry independently preserves results, page, scroll position, details, and sorting. Year/file-size sorting can fetch and globally sort up to 200 results in the background with cancellation. A native inspector shows a large cover, full description, ISBN, publisher, language, pages, series, file, and quota metadata; opening it now preserves the full results width, its description scrolls above the fixed import bar, and switching books refreshes both details and cover. Arrow keys select results, `Space` opens details, `Return` queues import, `⌘←`/`⌘→` changes page, and `⌘F` focuses search. Multiple books can be queued serially with per-item cancellation and imported/duplicate/failure summaries while the result surface stays open. Covers use memory/disk caching, bounded concurrency, off-screen cancellation, and distinct missing-cover/network-failure states; download history refreshes stale server-provided cover URLs in the background. Imported books persist Z-Library source IDs and ISBNs for more reliable duplicate detection.
- Niratan now ships one full-feature installer containing both book reading and video learning, with no separate Light or Video editions.
- The Reader image gallery, appearance, navigation, statistics, and Sasayaki now use consistent centered native panels with close buttons fixed at the top-right.
- The Sasayaki panel now separates Resources, Chapters, and Settings. Resources combines audiobook loading with subtitle matching, the playback header shows embedded artwork and metadata, and M4B chapter markers support direct seeking. The duplicate Bookshelf match action is removed, and Reader Go To opens on Chapters by default.
- Game Controller settings now expose the same complete action list and categories as Keyboard Shortcuts. Every playback, subtitle, audio, loop, transcript, and full-screen action can be bound while preserving existing Reader and Sasayaki mappings.
- Anki field mappings now use one combined editable menu field with a single macOS 26 Liquid Glass surface instead of layering native glass around the older gray material control. App upgrades continue to preserve custom and explicitly cleared mappings.

## 1.4.2

### 中文

- 修复从查词框点击放大镜时 Reader 仍停留在最前方，以及 Anki 首次创建浏览器窗口时可能显示上一次搜索的问题；现在会先把前台交给 Anki，再由 Anki 通过单次查询创建或更新浏览器窗口。
- 设置页的文本与密码输入框现在统一采用 macOS 26 风格的交互式玻璃胶囊外观，并保留清晰的键盘焦点提示；音频来源的添加按钮也改为配套的原生圆形玻璃按钮。
- 视频库会根据窗口宽度自动收纳搜索、排序、布局和来源操作；列表与海报模式也统一使用更易点击的分组展开/折叠标题，并改善侧栏与内容背景的玻璃层次。

### English

- Fixed the Reader remaining in front after the lookup magnifying-glass action and Anki's newly created Browser sometimes showing its previous search. Niratan now hands the foreground to Anki before one Browser request creates or updates the matching-note view.
- Settings text and secure fields now share a macOS 26-style interactive glass capsule appearance with a clear keyboard focus indication, and the audio-source add action now uses the matching native circular glass button.
- The Video library now condenses search, sort, layout, and source actions as the window narrows. List and poster layouts also share easier-to-click collapsible section headers with improved glass layering across the sidebar and content.

## 1.4.1

### 中文

- 主界面、书架、词典和设置统一采用 macOS 26 Liquid Glass 背景与原生玻璃控件，在浅色、深色和自定义主题下保持一致的桌面层次。
- Reader 新增书内图片库，可按正文顺序通过自适应多列网格浏览 EPUB 图片；尚未读到的插画会按字符进度保持模糊，打开大图后需再次点击才会解锁，预览支持按钮及左右方向键连续切换并保留图库位置。
- 合并内置“日语 EPUB”和“日语视频”为唯一的“日语” Profile；同一套 Anki 默认映射现在同时服务小说与视频，`{book-cover}` / `{sasayaki-audio}` 在视频制卡时会自动生成当前画面截图和字幕音频，因此 Anki 设置只保留一个默认映射按钮。
- Profile 现在统一由“设置 > Profiles”全局控制；书架、Reader 和 Video 不再提供各自的 Profile 切换，也不会因打开内容或切换窗口而隐式更换配置，从而避免重复加载词典与制卡设置。
- 修复启用英语 Profile 后 Video 字幕仍从点击字符按日语方式扫描的问题；现在点击英文单词中间也会从完整单词开头查词，与 Reader 一致。
- 修复大型内嵌 ASS 字幕可能让 Video 播放器卡死，以及 ASS 主台词高度与查词位置不一致的问题；字幕扫描、去重和时间线构建改为可取消的后台任务，普通底部主台词现在由同一个可见文本层负责显示、拖选、查词、高亮和弹窗定位，并会实时跟随字幕高度设置；切换 ASS 轨时不再先闪现完整 libass 字幕，作者定位文字、歌词、卡拉 OK、绘图和多层特效仍由内置 libass 保持原位渲染。
- 修复 Video 播放过程中保存进度可能引起周期性 CPU 升高的问题；现有播放位置、恢复选项和字幕选择会无损迁移，视频书架也不再因无关设置变化反复刷新。
- 修复部分 YouTube 历史视频没有字幕，以及逐词字幕把时间戳和 `<c>` 标签显示成正文的问题；现在优先使用发布者字幕，在没有发布者字幕时回退到自动字幕，并会重试此前缓存为空的字幕信息。
- Video 设置与播放器“视频”侧边栏新增 Anime4K 超分辨率，可选择关闭、快速或高画质；着色器按需下载并校验，默认关闭。
- Video 播放时，鼠标静止后光标会与底部控制栏同时隐藏；移动鼠标、离开播放器、打开学习界面或切换窗口后会恢复。
- Video Transcript 侧边栏新增“上一条 / 下一条”字幕对齐按钮，可将播放头左侧最近已结束或右侧最近未开始的字幕对齐到当前时间；默认快捷键为 `Shift+← / Shift+→`，并可在统一快捷键设置中修改。
- 修复查词框已检测到 Anki 重复卡片时放大镜仍为灰色的问题；现在会按当前重复检查范围找到已有笔记，点击放大镜即可在 Anki 中打开。
- 修复从查词框点击放大镜跳转 Anki 时，macOS 输入法与 WebView 焦点交接可能导致 Niratan 闪退的问题。

### English

- The main window, Bookshelf, Dictionary, and Settings now share a macOS 26 Liquid Glass background and native glass controls across light, dark, and custom themes.
- Reader now includes an in-book image gallery that lists EPUB images in reading order and opens any thumbnail in the existing full-screen image viewer.
- Merged the built-in Japanese EPUB and Japanese Video Profiles into one Japanese Profile. The same Anki defaults now serve books and videos: `{book-cover}` and `{sasayaki-audio}` automatically produce the current frame and subtitle audio during Video mining, so Anki Settings has one defaults action.
- Profiles are now controlled globally from Settings > Profiles. Bookshelf, Reader, and Video no longer switch Profiles independently or implicitly when content opens or window focus changes, avoiding redundant dictionary and mining-settings reloads.
- Fixed Video subtitles continuing to scan from the clicked character as Japanese after the English Profile was enabled. Clicking inside an English word now looks up from the full word's beginning, matching Reader behavior.
- Fixed large embedded ASS tracks potentially freezing the Video player and ASS primary dialogue drifting away from its lookup target. Subtitle scanning, deduplication, and timeline preparation now run as cancellable background work. Ordinary bottom dialogue uses one visible layer for rendering, selection, lookup, highlighting, popup anchoring, and live vertical-position changes. Switching ASS tracks no longer flashes the complete libass track first, while authored positioning, lyrics, karaoke, drawings, and layered effects remain fixed and rendered by bundled libass.
- Fixed periodic CPU spikes while Video saved playback progress. Existing positions, resume options, and subtitle selections migrate without data loss, and unrelated preference changes no longer refresh the video library.
- Fixed missing captions on some YouTube history items and karaoke captions rendering timestamps and `<c>` tags as text. Publisher captions remain preferred, automatic captions are used when needed, and previously empty caption metadata is retried.
- Video Settings and the player Video sidebar now offer optional Anime4K upscaling with Off, Fast, and High Quality presets. Verified shaders download on demand, and the feature defaults to Off.
- During Video playback, the pointer now hides together with the bottom controls after the same idle delay and returns on pointer movement, player exit, study overlays, or window deactivation.
- The Video Transcript sidebar now aligns the closest ended or upcoming subtitle to the current playback time with Previous/Next buttons. The default shortcuts are `Shift+Left/Right` and remain configurable in the unified shortcut settings.
- Fixed the lookup magnifying-glass button remaining disabled after an existing Anki card was detected. Duplicate checks now resolve matching note IDs in the configured scope so the notes can be opened in Anki.
- Fixed a possible Niratan crash during the macOS input-method and WebView focus handoff when the lookup magnifying-glass button opens Anki.

## 1.4.0

### 中文

- 查词框制卡成功后会在对应词条内显示放大镜按钮，点击即可让 Anki 打开并定位到刚添加的笔记；Reader、词典页和 Video 查词共用这一行为。

### English

- After a card is added, its lookup entry now shows a magnifying-glass button that opens Anki directly on the newly added note. Reader, Dictionary, and Video lookup surfaces share this behavior.

## 1.3.11

### 中文

- Reader 窗口会在关闭或正常退出 Niratan 前显式保存最后的普通窗口大小和位置；反复关闭、重新打开或重启 App 后打开书籍仍会恢复，并避免关闭过程中收缩的临时窗口覆盖记录。全屏状态不会覆盖普通窗口记录。

### English

- The Reader now explicitly saves its last windowed size and position before closing or quitting Niratan, restores them across repeated reopen and relaunch cycles, and prevents a transient teardown-sized window or full screen from overwriting the windowed frame.

## 1.3.10

### 中文

- 修复 Anki 设置在重启后丢失的问题：AnkiConnect 地址与 API Key、字段映射和标签现在会在编辑时立即保存；从非默认 Profile 修改全局连接设置时，也不会再覆盖默认 Profile 的牌组、模型、字段映射和重复检查选项。
- 修复手动清空 Anki 字段映射后，重启、重连或刷新牌组/模型信息时该字段可能被默认模板重新填入的问题；明确清空的映射现在会保持禁用。

### English

- Fixed Anki settings being lost after restarting the app. The AnkiConnect address and API key, field mappings, and tags now save immediately while editing. Updating global connection settings from a non-default Profile no longer overwrites the default Profile's deck, note type, field mappings, or duplicate-check options.
- Fixed manually cleared Anki field mappings being restored from default templates after restarting, reconnecting, or refreshing deck and note-type metadata. Explicitly cleared mappings now remain disabled.

## 1.3.9

### 中文

- Video 现在可直接添加或打开 YouTube 链接，支持在可用画质间切换、保存资料库与播放进度、字幕查词和视频制卡；字幕列表只显示视频发布者提供的原生字幕，不再下载自动生成字幕。“添加链接”窗口会明确标注此功能仍处于实验阶段。
- 修复通过“添加链接”打开 YouTube 时播放器窗口可能闪退，以及发布者字幕虽已列出却因空响应无法显示的问题。
- 修复 Video 窗口可被自由拉伸而产生黑边的问题；普通窗口现在始终按当前视频比例缩放，打开学习侧栏时仍保持视频画面比例，并避开原生全屏切换期间的窗口约束。
- 改进 Video 字幕与播放控制稳定性：字幕垂直位置现在使用相对实际视频画面的无数字顶部到底部滑杆，在字幕块能够容纳时可完整贴齐画面顶部或底部，并在窗口、全屏、不同显示尺寸及控制栏布局间保持相对位置；Compact Bottom 控制栏始终贴底，播放与倍速按钮不再叠加独立玻璃背景，点击视频其他位置可关闭倍速面板。
- Video 字幕调轴现在允许通过按钮或直接输入调整到 `-60000～60000 ms`，拖动条仍保留精调所需的 `-10000～10000 ms` 范围；超出拖动范围的偏移可以正确保存并在重开视频后恢复。

### English

- Video can now add or open YouTube links with available-quality switching, library and playback-history persistence, subtitle lookup, and video mining. Subtitle choices include only publisher-provided tracks and no longer download auto-generated captions. The Add Link sheet clearly labels this feature as experimental.
- Fixed a possible crash when Add Link opened the YouTube player, and publisher subtitles being listed but failing to display after an empty caption response.
- Fixed the Video window being freely stretched into letterboxing. Windowed resizing now follows the current video aspect ratio, keeps the video surface aspect-correct with the study sidebar open, and avoids window constraints during native full-screen transitions.
- Improved Video subtitle and playback-control stability: vertical placement now uses an unlabeled top-to-bottom slider relative to the fitted video picture, can align the complete subtitle stack with either edge when it fits, and preserves that relative position across windowed, full-screen, display-size, and control-layout changes; Compact Bottom stays anchored, play and speed no longer add separate glass backgrounds, and clicking elsewhere on the video dismisses the speed panel.
- Video subtitle timing now supports `-60000...60000 ms` through buttons or direct input while keeping the slider focused on `-10000...10000 ms`; offsets outside the slider range persist and restore when reopening the video.

## 1.3.6

### 中文

- 修复 Reader 查词弹窗内词典交叉引用无法用鼠标点击跳转的问题；跳转后即使关闭了常驻操作栏也会显示前进/后退控制，有声书播放控制存在时会合并为同一行并保持无底色的大点击区域。
- 修复 Reader 查词弹窗内选中文本后，鼠标移回阅读区会取消选区的问题；释义拖选越过弹窗边界后松开也会保留选中内容，Shift 悬停查词不受影响。
- 提升 Video 播放画质：Retina 屏幕现在按物理像素渲染，减少系统二次放大造成的发软；同时改进 10-bit、SDR 显示器色彩配置、可选 HDR/EDR 输出和屏幕刷新同步，并在硬件不支持时自动回退。
- 修复 Reader 统计在离开阅读窗口或统计面板后仍继续计时的问题；统计面板现在会实时刷新，并在面板处于焦点时继续计时，切到其他窗口或 App 后暂停且不会补算离开时间。
- 改进 Video 字幕在复杂画面上的可读性：字幕外观现在提供简洁的边缘样式与强度控制，可选择更深的柔和阴影、清晰描边或更强的高对比度描边，并为新用户默认启用高对比度样式。
- 修复多次打开和关闭 Reader 后，旧 Reader 实例可能在关闭时覆盖较新的阅读统计，导致当天已读字符数回退的问题。
- 修复按 Esc 关闭 Reader 窗口时，强制销毁 SwiftUI Hosting View 可能导致整个 App 崩溃的问题。

### English

- Fixed dictionary cross-references in Reader lookup popups not responding to normal mouse clicks. Redirect history controls now appear after a jump even when the persistent action bar is off, and share one background-free, generously clickable row with Sasayaki controls when audio is available.
- Fixed Reader lookup popup text selections being cleared when the pointer returned to the reading surface. Selections now also survive definition drags released beyond the popup boundary, without affecting Shift-hover lookup.
- Improved Video playback quality: Retina displays now render at physical-pixel resolution to avoid softness from an extra system upscale, with better 10-bit precision, calibrated SDR display color, optional HDR/EDR output, and display-synchronized presentation with automatic capability fallbacks.
- Fixed Reader statistics continuing after leaving the Reader window or Statistics sheet. The open Statistics sheet now updates live and keeps counting while focused, then pauses without backfilling inactive time after switching to another window or app.
- Improved Video subtitle readability on busy footage with compact Edge Style and Edge Strength controls for a darker Soft Shadow, Clear Outline, or a stronger High Contrast outline, which is now the default for new users.
- Fixed stale Reader instances overwriting newer reading statistics during window close after repeatedly opening and closing the Reader, which could make the day's character count move backwards.
- Fixed the app potentially crashing when Escape closed a Reader window while its SwiftUI hosting view was being torn down.

## 1.3.0

### 中文

- 项目正式更名为 Niratan，App、Xcode 工程、Light/Video scheme、DMG 产物名、更新检查和发布说明都改用新名称；bundle id 继续保留为 `moe.shishamo.hoshi` 以维持用户数据兼容，发布包会同时附带旧文件名以便旧版 App 内更新入口过渡。
- Reader 新增歌词模式：在已完成 Sasayaki SRT 匹配并导入音频后，可从 Reader 进入沉浸式同步歌词层；歌词视觉层使用 macOS Metal 渲染边界，支持无背景的当前行进度高亮、播放控制、查词弹窗、统计计数，并在退出时回到当前歌词对应的小说位置。
- 歌词模式新增“歌词遮罩”开关，播放时可把歌词柔化为模糊遮罩，并在鼠标悬停或查词弹窗打开时恢复清晰文本，横排和竖排歌词都会自动填满可用空间。
- 修复歌词模式和全局查词的弹窗定位：歌词查词会贴近歌词上下方，竖排长歌词会自动分列换行，当前播放歌词更稳定可查词；全局查词会优先贴近高亮选词，并保持父子弹窗的分层关闭行为。
- Reader 横排分页新增可选的双栏页面布局，并修复双栏下图片页、短文本章末尾和跨章翻页可能卡住的问题。
- 设置页的下载推荐词典和更新词典现在会先打开可勾选列表；手动更新会全量检查可更新词典的远端版本，手动导入且可识别来源的词典也会参与检测，并在更新后刷新候选状态，已经最新的词典不会再出现在更新列表中。
- 修复设置页进入词典折叠自定义后无法关闭的问题。
- 修复 Reader 和 Video 查词弹窗没有跟随词典双栏布局开关的问题，并保留弹窗内鼠标选中文本且不带振假名。
- Video 新增“快进字幕空档”开关，可按自定义速度在两句字幕之间临时加速播放，并在接近下一句字幕时恢复原播放速度。
- 修复 Video 大字号字幕在自动换成多行时底部文字可能被裁掉的问题。
- 修复 Reader 跳转面板的标注列表在部分 EPUB 目录重复指向同一章节时可能闪退的问题。
- 修复 Sasayaki 手动上一句/下一句在跨图片页或跨章节时可能停住、清掉高亮或跳到错误位置的问题。

### English

- The project is now officially named Niratan. The app, Xcode project, Light/Video schemes, DMG artifact names, update checker, and release notes use the new name, while the bundle id remains `moe.shishamo.hoshi` for user-data compatibility and release assets keep legacy filename aliases for older in-app updaters.
- Reader adds Lyrics Mode: after completing a Sasayaki SRT match and importing audio, you can enter an immersive synced lyrics layer; the lyrics visual layer now uses a macOS Metal render boundary with background-free current-line progress highlighting, playback controls, lookup popups, statistics counting, and an exit path back to the matching novel position.
- Lyrics Mode now includes a Lyrics Mask toggle that softens playing lyrics into a blurred mask, restores clear text on hover or while lookup popups are open, and lets both horizontal and vertical lyrics fill the available space.
- Fixed lookup popup placement in Lyrics Mode and global lookup: lyric lookups now appear above or below the lyric text, long vertical lyrics wrap into columns, the current playing lyric is more reliably lookupable, and global lookup prefers the highlighted selection while preserving parent/child popup dismissal behavior.
- Reader now offers an optional two-column horizontal page layout, with fixes for page turns that could stall on image pages, short chapter endings, and chapter boundaries.
- Recommended dictionary downloads and dictionary updates in Settings now open selectable lists; manual updates now check all update-capable dictionaries, include manually imported dictionaries with a recognized source, and refresh candidates afterward, so already-current dictionaries no longer appear in the update list.
- Fixed the dictionary collapse customization view in Settings so it can be closed after opening.
- Fixed Reader and Video lookup popups not following the Dictionary two-column layout toggle, while preserving mouse text selection inside popup entries without ruby annotation text.
- Video adds a Fast-forward Subtitle Gaps toggle that temporarily speeds playback at a configurable speed between subtitle lines, then restores the original speed near the next subtitle.
- Fixed Video subtitles with large font sizes being clipped at the bottom after wrapping into multiple visual lines.
- Fixed a crash in the Reader Go To highlight list when some EPUB table-of-contents entries point to the same chapter.
- Fixed Sasayaki manual previous/next cue navigation getting stuck, clearing highlights, or landing at the wrong position across image pages or chapter boundaries.

## 1.1.0

### 中文

- 书架右上角新增“统计”入口，可在书架内查看全局统计 Dashboard，包含今日、本周、阅读日历、趋势、书籍排行和书架对比。
- 统计 Dashboard 可直接调整每日字数/时长目标和每周达标天数，并用于进度和连续达标计算。
- 统计 Dashboard 新增书籍排行、速度摘要和书架对比；趋势图支持字数、时长、速度指标、柱状/折线样式，以及独立的日/周/月趋势粒度。
- 趋势图的柱状图和折线图支持悬停查看日期、指标值、字数、时长、速度和主要贡献书籍。
- 进入统计 Dashboard 时会先展示界面骨架，优先复用缓存快照，并在后台刷新本地统计数据，减少进入等待感。

### English

- Bookshelf now has a top-right Statistics entry that opens a global dashboard in Bookshelf, covering today, this week, the reading calendar, trends, book rankings, and shelf comparison.
- The Statistics dashboard now lets you adjust daily character/time goals and weekly target days directly for progress and streak calculations.
- The Statistics dashboard now includes book rankings, speed insights, and shelf comparison, and the trend chart supports character, duration, and speed metrics, bar/line styles, and independent day/week/month grains.
- Trend bars and line points now show hover details with date, metric value, characters, duration, speed, and top contributing books.
- Opening the Statistics dashboard now shows the dashboard skeleton immediately, reuses cached snapshots first, and refreshes local statistics in the background.

## 1.0.1

### 中文

- 全局查词的连续查词和嵌套弹窗现在会在独立面板中打开，减少覆盖或挤压主查词窗口的情况。
- Reader 打开本地书籍时不再短暂显示“无法打开书籍”，也不会因此把独立阅读窗口缩成小尺寸。

### English

- Global lookup follow-up searches and nested popup stacks now open in separate panels, reducing cases where they cover or squeeze the main lookup window.
- Reader no longer briefly shows the failed-open state while loading local books, preventing that transient state from shrinking the dedicated Reader window.

## 1.0.0

### 中文

- Niratan Mac 进入首个原生 macOS 稳定正式版，继续提供 Light 和 Video 双安装包，覆盖小说阅读、查词、Google Drive 同步、Anki 制卡和 Video 学习播放器。
- Google Drive 登录凭据现在合并为单个钥匙串项，设置页和自动同步状态刷新不再反复读取 token 明文，减少连续出现 macOS 钥匙串授权弹窗的情况。

### English

- Niratan Mac is now the first stable native macOS release, continuing to provide separate Light and Video installers for novel reading, lookup, Google Drive sync, Anki card creation, and the Video study player.
- Google Drive credentials are now bundled into one Keychain item, and Settings/auto-sync state refreshes no longer repeatedly read token secrets, reducing repeated macOS Keychain permission prompts.

## 0.6.6

### 中文

- Google Drive 登录凭据现在合并为单个钥匙串项，设置页和自动同步状态刷新不再反复读取 token 明文，减少连续出现 macOS 钥匙串授权弹窗的情况。

### English

- Google Drive credentials are now bundled into one Keychain item, and Settings/auto-sync state refreshes no longer repeatedly read token secrets, reducing repeated macOS Keychain permission prompts.

## 0.6.5

### 中文

- Reader 会迁移旧版过小或离屏的窗口尺寸记录，重新打开时优先回到当前屏幕的可见区域。
- Google Drive 登录凭据存储对齐当前 macOS App 身份和上游账号键名，减少升级或重连后认证状态不一致的情况。

### English

- Reader now migrates outdated tiny or off-screen saved window frames so reopening a book returns to the current display's visible area.
- Google Drive credential storage now follows the current macOS app identity and upstream account-only keys, reducing inconsistent auth state after upgrades or reconnecting.

## 0.6.4

### 中文

- Video 悬浮与贴底控制栏继续打磨按钮、菜单、时间轴预览和紧凑布局表现，让两种布局使用同一套播放状态与交互管线。
- 设置页的词典和音频来源排序改为列表内拖拽手势，修复部分 macOS 26 环境下拖动排序不稳定的问题。
- Reader 新窗口默认位置会落在当前可见屏幕内，减少外接显示器切换后窗口出现在屏幕外的情况。

### English

- Video floating and compact-bottom controls have been polished across buttons, menus, timeline previews, and compact layout behavior while sharing the same playback state and interaction pipeline.
- Dictionary and audio-source ordering in Settings now uses in-list drag gestures, fixing unreliable reorder behavior on some macOS 26 setups.
- New Reader windows now default to a visible screen frame, reducing cases where windows appear off-screen after external display changes.

## 0.6.3

### 中文

- Video 设置新增控制栏布局选项，可在默认悬浮控制栏和贴底紧凑控制栏之间切换。
- 贴底紧凑控制栏减少播放画面中央遮挡，并同步调整字幕、弹窗和时间轴预览的底部避让距离。

### English

- Video settings now include a control bar layout option for switching between the default floating controls and a compact bottom-aligned control bar.
- The compact bottom control bar reduces obstruction in the center of the video and adjusts subtitle, popup, and timeline-preview bottom clearances accordingly.

## 0.6.2

### 中文

- 检查更新入口恢复为可见按钮；发现新版本后可直接在 App 内下载对应 Light 或 Video DMG，校验后打开安装包，不再需要手动去 GitHub Releases 查找。
- Reader 独立窗口会记住上次关闭时的大小和位置，再次打开书籍时不再每次重置为默认窗口。
- 修复横排 Reader 查词弹窗在窗口边缘附近定位不稳定的问题，减少弹窗贴边或偏离选中文本的情况。

### English

- Restored a visible update-check entry. When a new version is available, Niratan can now download the matching Light or Video DMG in-app, verify it, and open the installer instead of sending users to GitHub Releases.
- Reader windows now remember their last size and position instead of resetting to the default frame every time a book is opened.
- Fixed unstable lookup popup placement near window edges in horizontal Reader layout, reducing cases where the popup hugs an edge or drifts away from the selected text.

## 0.6.1

### 中文

- Video 字幕导入新增 ASS/SSA 支持，可提取 Dialogue 文本用于字幕列表、查词和挖卡，样式渲染仍交由 mpv 处理。
- Video 资料库的列表和海报视图会为可见条目补齐缺失缩略图，播放窗口打开期间则暂停后台缩略图生成，减少播放和打开视频时的磁盘抢占。
- Video 制卡截图和音频片段导出共用一次后台媒体生成窗口，制卡可更快返回，并在导出完成后自动恢复资料库缩略图任务。
- 使用稳定发布证书签名的 DMG 更新后，更容易保留 macOS 全局查词所需的无障碍授权，减少升级后重新授权的情况。

### English

- Video subtitle import now supports ASS/SSA files and extracts Dialogue text for transcripts, lookup, and card mining while leaving styled rendering to mpv.
- Video library list and poster views now fill in missing thumbnails for visible items, while background thumbnail generation pauses for the duration of an open player window to reduce disk contention during playback and video opening.
- Video card mining now shares one background media-generation window for screenshots and audio clips, returns to card creation faster, and resumes library thumbnail work after export finishes.
- DMG updates signed with the stable release certificate are more likely to preserve the macOS Accessibility permission used by global lookup, reducing the need to reauthorize after upgrading.

## 0.6.0

### 中文

- 正式完成从 Mac Catalyst 到原生 macOS App 的迁移，保留书籍、进度、bookmark、sidecar、词典、Anki 配置和 Google token 的升级兼容路径，并继续使用 `moe.shishamo.hoshi` 作为 App 身份。
- 新增 Light 和 Video 两个原生构建。Video 版本内置 universal libmpv，Light 版本不包含 mpv；两个版本共享用户数据，但不要同时运行。
- 新增独立 Profile、日英内容配置、书籍语言自动选择、Profile 独立词典/Reader 外观/Anki 映射，以及兼容旧备份的词典备份恢复。
- 新增英语单词和短语查词、撇号/连字符扫描、IPA 字段输出、近似词数进度，以及小说/动漫两套默认 Anki 映射。
- Reader 新增可复用原生阅读窗口、书内搜索、章节/搜索/高亮统一跳转面板，并修复窗口缩放、全屏、竖排、图片/SVG、快捷键重复触发和失败返回路径。
- Sasayaki 恢复 SRT 匹配，改进播放/跳句/关闭 Reader/退出 App 时的播放位置保存，并在同步时导入更新的 Sasayaki 位置。
- 书架新增 EPUB 拖放导入、本地书籍手动排序、导出面板定位修复、封面缩略图稳定性改进，以及更紧凑的封面与进度显示。
- Popup 与词典新增大尺寸双栏释义布局、跨 App 选中文本查词和剪贴板回退读取，并修复词典设置重启回退、重复制卡状态和上下文选择体验。
- Google Drive 同步恢复书籍刷新入口，支持后台多本下载、进度显示、较短网络超时、短暂离线降噪和 Sasayaki 位置同步。
- Video 新增本地资料库，可添加文件夹、扫描视频、搜索、排序、按继续观看/未观看/已完成/缺失/最近/系列/文件夹/合集/收藏/待复习浏览，管理本地标题、标签、备注、合集和绑定字幕。
- Video 资料库新增海报缩略图、智能集合、现代化控件和主题自适应玻璃背景；缩略图生成通过单任务后台调度器运行，并在播放、查词和制卡时暂停。
- Video 播放器新增独立播放窗口、播放列表、拖放导入、字幕/音频/章节轨道、位置和字幕状态恢复、紧凑悬浮控制栏、底栏 Profile、单击播放、双击全屏和统一快捷键。
- Video 播放体验新增硬件解码、反交错、HDR、亮度/对比度/饱和度/Gamma/色相调节、滚动调节音量、时间轴悬停预览、窗口比例适配和稳定的原生全屏退出。
- Video 字幕支持 SRT/VTT 和内嵌文字轨解析、点击/Shift 悬停查词、选择复制、字幕列表、章节列表、挖卡历史、字重/阴影/背景/垂直位置/高亮文字色和 50 ms 时间校准。
- Video 制卡支持 `{video-screenshot}` 和 `{video-audio-clip}`，会先做重复检查和字段映射预检，跳过未映射媒体，并优先直接写入 Anki `collection.media` 后台完成截图/音频生成。
- 设置页拆分 Reader/Video 分组，统一键盘快捷键和手柄控制入口，新增 AnkiConnect API key，并修复 macOS 26 设置背景、拖放排序和快捷键设置崩溃。

### English

- Completed the migration from Mac Catalyst to a native macOS app while preserving upgrade paths for books, progress, bookmarks, sidecars, dictionaries, Anki configuration, and Google tokens. The app identity remains `moe.shishamo.hoshi`.
- Added separate native Light and Video builds. The Video build bundles universal libmpv, while the Light build does not include mpv. Both variants share user data, but should not be run at the same time.
- Added independent Profiles, Japanese and English content setup, automatic book-language selection, Profile-specific dictionaries, Reader appearance and Anki mappings, plus dictionary backup/restore compatibility with older backups.
- Added English word and phrase lookup, apostrophe/hyphen-aware scanning, IPA field output, approximate word-count progress, and separate default Anki mappings for novel and anime cards.
- Reader now has a reusable native reader window, in-book search, and a unified jump panel for chapters, search results and highlights, with fixes for resizing, full screen, vertical layout, images/SVGs, duplicate shortcuts, and failed-load recovery.
- Sasayaki SRT matching is restored, and playback position now survives playback, cue jumps, Reader window close, app quit, and sync import of newer Sasayaki positions.
- Bookshelf now supports drag-and-drop EPUB import, manual local-book ordering, steadier export sheet placement, more stable cover thumbnails, and denser cover/progress presentation.
- Popup and Dictionary now support an optional two-column glossary layout, cross-app selected-text lookup with clipboard fallback, and fixes for Dictionary settings persistence, duplicate-card status and context selection.
- Google Drive sync restores the book refresh entry, supports background multi-book downloads with progress, shorter network timeouts, quieter transient offline handling, and Sasayaki position sync.
- Video adds a local library for folders, scanning, search, sorting, Continue Watching, Unwatched, Finished, Missing, Recent, Series, Folders, Collections, Favorites and Needs Review, plus local titles, tags, notes, collections and bound subtitles.
- Video library adds poster thumbnails, smart collections, modern controls and theme-adaptive glass backgrounds. Thumbnail generation now runs through a single-worker scheduler that pauses during playback, lookup and card media export.
- Video playback adds a dedicated player window, playlist handling, drag-and-drop import, subtitle/audio/chapter tracks, playback and subtitle-state restore, compact floating controls, bottom-bar Profile switching, click play/pause, double-click full screen, and unified shortcuts.
- Video playback now includes hardware decoding, deinterlacing, HDR, brightness/contrast/saturation/gamma/hue controls, scroll-to-adjust volume, timeline hover previews, aspect-ratio fitting, and stable native full-screen exit.
- Video subtitles support SRT/VTT and embedded text tracks, click and Shift-hover lookup, selection/copying, transcript, chapters, mining history, font weight, shadow, background, vertical position, highlight text color, and 50 ms timing adjustment.
- Video mining supports `{video-screenshot}` and `{video-audio-clip}`, performs duplicate and field-mapping preflight before media work, skips unmapped media, and writes directly to Anki `collection.media` while screenshot/audio generation finishes in the background.
- Settings separates Reader and Video groups, centralizes keyboard shortcuts and game-controller controls, adds AnkiConnect API key support, and fixes macOS 26 settings backgrounds, drag reordering, and keyboard shortcut settings crashes.

## 0.6.0 Beta 4

- Added experimental, opt-in cross-App selected-text lookup: press the configurable global shortcut to show the active Profile's Niratan dictionary Popup near the pointer without copying text through the clipboard.
- Fixed Reader appearance settings reverting to an older Profile snapshot after relaunching the app.
- Fixed Dictionary and Audio source rows failing to reorder on macOS 26 by committing row drops through an AppKit pasteboard destination.
- Fixed Reader left/right shortcuts occasionally advancing two pages when AppKit rewrapped one key event before delivering it to the focused WebView.
- Reorganized Settings so Video has its own group, keyboard shortcuts and game controllers have a separate controls group, and Video Settings no longer duplicates the shortcut inventory.
- Video subtitles now support native mouse selection and copying while preserving click and Shift-hover lookup, and the matched lookup text remains highlighted until the Popup closes.
- Video subtitle options now customize both subtitle text color and lookup-highlight background color from Settings or the inspector.
- Mining History, Transcript and Chapters now use the same fully clickable Liquid Glass cards, with a brighter study sidebar in light appearance and the approved subtitle lookup highlight color as the default.
- Reader and Video Popup entries now offer a shared card-stacked context selector with independent add/rollback controls for preceding and following sentences; expanded Video context also expands the captured audio range.
- Opening Video from the main sidebar now chooses a media file first and presents it in one dedicated player window; choosing another file reuses that window, while closing it saves playback state and stops the player.
- Fixed videos opened from the main sidebar showing a black frame when the initial media request arrived before the libmpv render surface was ready.
- Moved Mining History and Open Video into the widened bottom playback bar, synchronized native traffic-light visibility with its two-second idle hide, and restored full-screen support for the dedicated Video window.
- Replaced windowed Video letterbox black with a restrained, current-frame Liquid Glass ambience while keeping full-screen letterboxing pure black and card screenshots unchanged.
- Video now restores both the last playback position and the selected embedded, external, or disabled subtitle state when reopening files or switching episodes from the inspector.
- Fixed the Video playback bar and top-left controls remaining visible indefinitely when the pointer stopped over them; both now hide after two seconds without pointer movement.

## 0.6.0 Beta 2

- Restored the Google Drive book refresh button in the native Bookshelf toolbar when sync is enabled and connected.
- Google Drive book downloads now stay in the background with per-book progress, allowing multiple books to download at the same time without blocking the Bookshelf.
- Audio sources in Settings can now be reordered by dragging any row, including the local audio source, and keep their lookup priority across launches.
- Fixed the selected Video Profile being overwritten by the global Profile after visiting Settings or switching app sections.
- Restored Shift-hover lookup in Reader and added the same configurable, continuous Shift-hover lookup to Video subtitles.
- Fixed dictionary rows in Settings no longer supporting drag-and-drop ordering after the native settings migration.

## 0.6.0 Beta 1

- Fixed GitHub release builds being terminated at launch on Apple Silicon by preserving a valid ad-hoc signature across the App and embedded libraries.

## 0.6.0 Beta

- Added Japanese and English Profiles with independent dictionary, Reader appearance and Anki mining settings, automatic EPUB language selection, per-book override and separate built-in `Japanese EPUB` / `Japanese Video` defaults.
- Added English word and phrase lookup, apostrophe/hyphen-aware scanning, IPA output for Lapis/Yomitan-compatible Anki fields and approximate word-count progress.
- Updated dictionary backup and restore to preserve Profile dictionary configuration while remaining compatible with older single-Profile backups.
- Added Video media mining that captures the current frame and encodes the selected audio track over the subtitle range for normal Anki field mappings.
- Added Video pointer-revealed playback chrome that auto-hides on idle or app/window exit, uses a compact IINA-like draggable control surface, single-click play/pause, double-click full screen, subtitle, volume, track, and shortcut-summary controls.
- Changed the macOS app bundle identifier to `moe.shishamo.hoshi`.
- Raised default Video subtitle placement so captions are not covered by the compact playback controls.
- Added Video drag-and-drop import for media and SRT/VTT subtitle files, and preserved playback when switching from Video to other sidebar sections and back.
- Added Video subtitle appearance controls for font and size, with asbplayer-style defaults, plus mask controls for blurring or hiding text subtitles until pointer hover.
- Added an asbplayer-style Video Mining History that saves the current subtitle independently of Anki, supports configurable retention, and can reopen the source video/subtitle for later lookup and card creation.
- Moved the Video subtitle list beside Mining History with a segmented switch, and made selected embedded text tracks populate the complete list without requiring a separate subtitle import.
- Moved Video chapter navigation into the same segmented study sidebar as Mining History and the subtitle list, with current-chapter highlighting.
- Fixed SVG and other Reader images being cropped or rendered incorrectly in the native macOS full-screen image preview.
- Restored Catalyst-style Reader layout so text uses the full available viewport and only applies the reader margins chosen in Appearance.
- Expanded the native Reader into the top safe area so vertical pages can use the titlebar band instead of leaving a large blank strip.
- Fixed Reader previous/next shortcuts changing chapters before the final partial page had been displayed.
- Fixed Sasayaki playback shortcuts so `P` continues to play/pause while the Sasayaki panel is open.
- Fixed Reader previous/next shortcuts firing twice when the focused WebView also received the same key event.
- Fixed Reader and Sasayaki shortcuts crashing on macOS 27 when a key event was successfully handled.
- Restored the Bookshelf cover size and compact progress bars to the denser v0.5.0 Catalyst-style layout.
- Fixed the nested Dictionary Settings page trapping the main sidebar, and placed its lookup/display options directly on the Dictionary settings page.
- Restored Sasayaki SRT matching from the native Bookshelf with the grouped v0.5.0-style match sheet.
- Added safe novel and anime default Anki mappings for Lapis, Kiku, and Senren. Novel `SentenceAudio`/`Picture` use Sasayaki audio and book covers; anime defaults use Video audio clips, screenshots, and subtitle-time source info, with separate confirmed restore actions.
- Moved the Video Profile selector from the top-right overlay into the bottom playback controls where the active Profile name remains visible.
- Fixed Reader `{book-cover}` cards omitting the active book cover and Video `{video-audio-clip}` cards silently losing audio for formats such as MKV.
- Fixed Video Previous Subtitle restarting the current subtitle instead of seeking to the preceding cue.

## 0.4.2

- Fixed vertical reading pages where some EPUBs could show text from adjacent pages stuck together or overlapping at pagination boundaries.
- Aligned vertical reader page sizing and bottom spacing with upstream behavior while preserving Mac horizontal overflow protection.
- Restored direct switching between Books, Dictionary, and Settings from the reader so returning to Books can continue the current reading session.

## 0.4.1

- Added dictionary entry navigation shortcuts for lookup results.
- Added shortcut settings for previous and next dictionary entry navigation.
- Improved highlighting and scrolling for the current dictionary entry in popup and nested popup results.

## 0.4.0

- Merged recent upstream reader and dictionary behavior with Mac Catalyst adaptations.
- Improved reader full-screen and chrome layout so the reading area uses more of the window.
- Fixed reader white-screen and vertical pagination display regressions.
- Added right-click delete actions for highlights and dictionary entries to match trackpad swipe delete behavior.
- Improved localization coverage for new settings surfaces.
- Improved Google Drive progress sync behavior around unchanged progress across days.
