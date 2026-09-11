# Niratan Mac Architecture Refactoring

This document records long-term architecture direction. It is not an execution log.

## Principles

- Preserve Mac user-visible behavior before matching iOS implementation details.
- Keep Reader, popup lookup, AnkiConnect, local audio, Sasayaki, and sync boundaries explicit.
- Prefer small, testable state transitions over broad root-view rewrites.
- Treat WKWebView layout, injected CSS, and JavaScript bridge changes as high-risk API changes.
- Keep SwiftUI screens where possible and use narrow AppKit boundaries instead of duplicating screens.

## UIKit To AppKit Migration

The native Mac migration plan is now `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`.

Long-term direction:

- Keep current SwiftUI feature screens, models, and services unless a real Mac behavior gap appears.
- Do not preserve iOS compatibility branches merely for theoretical reuse; this repository is the Mac product.
- Remove iOS-only paths first where doing so does not change Mac behavior.
- Do not reintroduce UIKit or a Catalyst target.
- Keep Reader/WebView, popup coordinate handling, Google Drive sync, AnkiConnect, LocalFileServer, word audio, and Sasayaki behavior stable during native hardening.

## Reader Navigation

The stable target is a root navigation model where Books, Dictionary, and Settings remain predictable while the reader can preserve the current reading session.

Open questions to resolve before another Reader navigation rewrite:

- Whether Reader should remain a Books `NavigationStack` destination or become a Mac-specific scene/overlay.
- How root navigation should remain reachable without Reader owning a duplicate root tab control.
- How full-screen focus mode should enlarge the reading area without causing toolbar or safe-area relayout flicker.

## Reader WebView And Pagination

Long-term direction:

- Keep vertical and horizontal pagination logic close to upstream behavior where it is browser-layout compatible.
- Isolate Mac-only overflow protections so they do not destabilize vertical writing.
- Add small deterministic checks for generated reader CSS and JavaScript bridge invariants.
- Maintain a manual visual test set that includes vertical Japanese EPUBs, long chapters, images, and chapter boundaries.
- Keep Reader visual validation tied to actual EPUB data in the exact native App. Lightweight contracts can guard bridge/static behavior, but generated fixtures, Debug Lab automation, and pixel baselines must not be treated as proof of safe-area or pagination correctness.

## Dictionary And Popup Rendering

Long-term direction:

- Keep dictionary page and popup rendering paths aligned.
- Avoid separate CSS compatibility layers for popup-only fixes.
- Preserve dictionary media handling for hoshidicts/Yomitan data rather than replacing broken content with generic placeholders.
- Treat `PopupPresentationCoordinator` and `PopupView` as reusable lookup presentation boundaries. Reader and Video provide selection geometry and mining context; neither owns a separate dictionary renderer.

## Profiles And Content Language

- Treat the active global Profile as the only runtime configuration choice. `Settings > Profiles` is the sole selector; Bookshelf, Reader, Video, Dictionary, Popup, nested lookup and mining consume that same selection.
- Keep sidebar navigation, Reader/Video window focus, book opening and detected content language Profile-neutral. They may adapt language processing to the content, but must never activate another Profile or trigger an implicit dictionary/Anki reload.
- Preserve legacy `BookMetadata.profileId`, UserDefaults `videoProfileID` and `ProfileIndex.primaryProfileIdsByLanguage` values when reading and writing existing data, but exclude them from runtime resolution. `Japanese` is the sole built-in Profile; merge an equivalent legacy `default-ja-video` configuration into it, while preserving any divergent customized legacy Profile under its original ID as an ordinary non-default global choice.
- Keep physical dictionary data and AnkiConnect transport global. Profile-owned state is limited to dictionary enable/order/display, Reader appearance and Anki mining mappings.
- Carry the active global Profile ID through Reader, Popup, nested lookup and mining so every surface uses one consistent dictionary, appearance and card-mapping configuration.
- Preserve `default-ja` legacy projections and merge profile-aware dictionary backups without overwriting Reader or Anki Profile files.
- Language processors belong at the lookup/selection boundary. Stored bookmarks and statistics remain raw character positions; English only converts those values for approximate-word display and input.

## Manga Learning

Long-term direction:

- Keep all local and remote Manga entry points behind `MangaReadingSession` and `MangaPageContentProvider`. A remote card or chapter click hands a provider-neutral `MangaRemoteReadingRequest` to the AppKit-owned reader window; that window owns the cancellable async bootstrap and replaces only its content with the shared `MangaReaderView`. The native reader, OCR, Popup, nested lookup, and Anki mining must not depend on local, Suwayomi, or Aidoku transport details.
- `SuwayomiClient` remains a narrow connector to an existing Server. Suwayomi owns extension installation/configuration, source HTTP behavior, cookies, server library and chapter progress; Niratan keeps its configuration, credentials, library and cache semantics Profile-scoped.
- Aidoku `.aix` is the sole permitted in-process third-party Manga source-code boundary. The local `AidokuRuntime` uses vendored interpreter-only Wasm3, pinned SwiftSoup and the public MIT `aidoku-rs` ABI/Postcard format. Package validation, 64 MiB memory capping, timeout/cancellation, restricted imports, bounded networking and atomic update/migration prevent sources from receiving file-system, Keychain, other App-data, or arbitrary native access. Never copy/link restricted official `AidokuRunner`, restore Shinsou, add Java/Mihon APKs, JIT, XPC/helper executables, or introduce a second reader.
- Keep `manga_library.json` local-only. Aidoku source lists, packages, non-sensitive settings, library, progress and cache are App-global and stored separately; credentials and opaque source-authored values use an Aidoku-specific Keychain service. Removing a source preserves its library/progress identities as unavailable, while removing a source list never uninstalls a package.
- Keep manga as a native macOS module with its own catalog, page-provider and reading-progress models. Do not represent image pages as EPUB chapters or make the existing Reader WebView responsible for archive access.
- Reuse the Bookshelf presentation boundary for novels and manga: local, browse, and online-library cover cards use the shared fixed-ratio `ShelfBookCard`/`ShelfCoverFrame`; only library items provide a progress value. Progress strips, collapsible sections, drag feedback and shelf management stay shared SwiftUI components, while `BookshelfViewModel` and `MangaLibraryViewModel` retain separate storage and feature actions. Manga shelves, manual order and Reading visibility are independent from novel preferences. Both library surfaces place navigation and library actions in the native macOS 26 window toolbar, and use the same material-free page background and direct single-layer `glassEffect` cards/management sections; do not place `Material` or grouped Form chrome underneath those glass components. Shelf management reuses the Reader/Sasayaki `NativeReaderSheetPanel`, uses its top-right close action, a native switch, the shared AnkiConnect-style `nativeSettingsTextField`, and a plain Add action instead of a toolbar Done button, checkbox, filled button or rounded Material text field.
- Keep the manga catalog model owned by the persistent main root rather than recreating it when the sidebar section appears. Start its snapshot load with the root, retain the current catalog across section switches, and distinguish “not loaded yet” from a genuinely empty catalog so the import empty state is never used as a loading placeholder.
- Treat folder, CBZ and ZIP sources as read-only user media. Persist security-scoped bookmarks and Niratan-owned metadata only; source removal, refresh, cover generation and reading must never rename, move, rewrite or delete source files.
- Treat each newly selected ordinary image folder as one non-recursive manga source whose immediate supported images are its pages. Ordinary CBZ/ZIP sources likewise form one naturally sorted manga when no valid Mokuro metadata is present; ignore archive hidden/resource-fork entries, keep legacy recursive folder records decode-only, and preserve Mokuro metadata-first multi-book splitting when valid metadata exists.
- Removing a manga card is a persistent library-index action, not a source-file deletion. Refresh preserves the hidden state, while explicitly importing the same source restores its hidden items; source management remains the only whole-source removal path.
- Keep archive access lazy and bounded. Reject unsafe paths and oversized expanded entries, naturally sort supported image names, cache decoded page data in memory, and avoid extracting whole archives to Application Support.
- Present reading in a dedicated AppKit-owned window with native SwiftUI content. Single-page, direction-aware double-page and continuous layouts share one page loader, progress store, persisted bounded page-zoom percentage, OCR-region loader and native lookup overlay. Paged layouts apply the selected 50%–200% scale relative to one centered AppKit fit magnification, while continuous pages adjust their lazy-stack width and reuse that canvas's hit-testing and text rendering at the selected fitted size; the toolbar exposes one compact macOS 26 glass slider and exact input over this single value without a parallel preset model, and both pages in a paged spread share its magnification, scroll geometry and fixed gutter. Keep paged desktop inputs deliberately separate at every zoom: thresholded discrete mouse-wheel input turns pages, precise trackpad scrolling pans the native canvas, and Command/Control-scroll changes the same persisted zoom value around the pointer.
- Keep scan-page processing inside Manga's native page-provider boundary. Detect wide pages from their post-crop dimensions, optionally split them into virtual display pages in the existing RTL/LTR reading order, and optionally trim only contiguous near-white outer scan rows/columns with bounded analysis. Display-page navigation, OCR hit regions and canvas actions consume the derived crop, but catalog progress continues to persist the source-image index and source media is never rewritten. Desktop Manga does not need the phone-oriented rotate-to-fit mode or a second split-order override beyond the existing reading direction.
- Keep page-level desktop actions on the native canvas boundary. Secondary-button movement pans the enclosing scroll view; a secondary click resolves the exact page under the pointer before offering copy, PNG save, system share and custom-cover actions. Custom covers are derived into an app-owned stable cache path and preserved by source rescans without writing to the source media.
- Continuous page canvases intercept Command/Control-scroll before SwiftUI's outer two-axis scroll view, resolve the next bounded zoom through the same wheel resolver as paged mode, and write it back to the shared persisted percentage. Unmodified precise scrolling must continue to reach the outer continuous scroll view.
- Use macOS 26 system controls and Liquid Glass APIs for manga surfaces. Do not add SwiftUI Material backgrounds or rebuild the existing repository glass components around Material.
- Keep page text behind one service boundary with Mangatan's source priority. Resolve existing Mokuro metadata before any OCR: image-directory items first look for same-basename sibling `.mokuro` and `.json` sidecars, then in-directory `.mokuro`, `mokuro.json` and other `.mokuro` files; archive items look for adjacent basename `.mokuro` and `.json` files. Match pages by image basename before index fallback, convert `box`/`lines_coords` pixel geometry into the native canvas, and enable hover/lookup automatically without the OCR toggle or a network request. Only pages without Mokuro metadata may use the Chromium Google Lens protobuf upload endpoint after an explicit whole-manga OCR action and first-use network disclosure; resize uploads to a bounded 1,500-pixel JPEG. Start the background queue at the current page and wrap to the beginning, with visible progress and cancellation. Persist each completed page atomically in Application Support, including empty results, and validate the cache against its schema, OCR engine signature, source modification date and complete stable page-path list before reuse; never place generated sidecars beside or inside user media. Preserve each Mokuro block or Lens paragraph as one reading-order text block while mapping its lines into per-character hit regions, including right-to-left columns and top-to-bottom vertical text. Match Mangatan's overlay behavior: passive text is invisible; hovering or selecting reveals every line in the active block on a translucent white rectangle with scaled black text, and the matched range receives the accent highlight. Lookup begins at the pointed character, while `SelectionData.sentence` and the mining context carry the entire block directly into card creation. Manga mining attaches the hit region's page index and lazily loaded original page data to `MiningContext`; `{book-cover}` fields consume that page through the shared compressed/content-hashed Anki image pipeline, including the correct page in a double-page spread, without changing Reader cover or Video screenshot semantics. Manga anchors Popup to the union of the complete block: horizontal blocks center the Popup directly above or below, vertical blocks center it directly left or right, with edge-aware flipping. This centered placement is an opt-in Manga parameter whose shared default remains off, so Reader, Video, Dictionary and global lookup retain their existing placement. Keep Google requests cancellable, ephemeral and timeout-bounded; the unofficial endpoint failing must retain completed cache entries and leave Mokuro and local image reading usable. Manga text interaction does not use `WKWebView`. Clicking blank canvas space closes the popup without adding a separate close control. Dictionary lookup, nested popup, audio and mining reuse the existing shared services.

## Video Learning

Long-term direction:

- Ship one full-feature native target in which Reader and Video compile together; do not reintroduce build-variant feature flags.
- Keep `PlaybackEngine` independent from SwiftUI and isolate libmpv C/Objective-C++ integration in `Features/Video/Playback/`.
- Keep display correctness inside that native render boundary: render `CAOpenGLLayer` surfaces at the active screen's backing-pixel scale, prefer half-float precision with accelerated 8-bit fallback, supply SDR ICC through the libmpv render API, promote compatible opt-in HDR to macOS EDR/PQ, and bind swap reporting to the active display with an immediate fallback. During AppKit live resize, the layer must draw asynchronously and reject main-thread draw requests so mpv rendering cannot block window tracking. These correctness paths must not introduce SwiftUI-owned OpenGL state or subjective sharpening profiles.
- Parse subtitle documents into Niratan-owned cues for lookup, transcript navigation and mining. ASS/SSA follows Fushi's two-mode text ownership: default to the user's uniform subtitle appearance, deduplicating identical active text; Respect ASS Styles uses native attributed text with authored fonts, colors, alignment, margins, positioning, movement and fades. Both modes draw and hit-test the same TextKit glyphs, including positioned/lyric/KFX text. Only separate non-text drawing events may use the filtered libass effects track; an effects failure must not replace selectable text with native-only rendering. Complex clipping, rotation, transforms, animated karaoke and mixed drawing/text events are not yet fully reproduced.
- Keep playback history out of the shared preferences hot path. Legacy `UserDefaults` dictionaries are migration inputs only; periodic progress, resume options and subtitle selections live in a small dedicated Application Support file behind one process-shared memory snapshot, and library updates use media-identity-scoped notifications rather than broad defaults observation.
- Keep media opening and subtitle import non-blocking on the main actor. Folder playlist discovery, large subtitle parsing, and transcript construction are background work; the UI should first load the selected media and show a bounded current-time transcript window.
- Keep Video import entry points aligned: picker imports and drag-and-drop must route through the same media/subtitle loading functions so mpv sidecar behavior, Niratan overlay parsing, transcript construction, and mining context stay consistent.
- Keep Anime4K as an optional Video-only enhancement behind `PlaybackEngine`: Settings owns the persistent default and the player Video inspector applies the same strong-typed Off/Fast/High Quality preference live. Only pinned Anime4K v4.0.1 files may be downloaded into Application Support after size, UTF-8 hook and SHA-256 validation; mpv receives manager-owned file URLs through ordered `change-list glsl-shaders` commands. Shader downloads remain opt-in and pass through the playback boundary.
- Keep Video playback state owned by a persistent Video detail surface rather than by transient sidebar selection. Switching to Bookshelf, Dictionary, or Settings may hide the Video surface and unregister Video shortcuts, but it should not tear down mpv or release the current media URL until the window/app actually closes.
- Treat mpv subtitle loading as a best-effort renderer/track alignment path. Niratan-owned parsed subtitles remain the source for overlay lookup, transcript navigation, and mining even when mpv rejects a path or format.
- Keep playback chrome lightweight and video-local: windowed playback uses full-size content beneath a native titlebar visual-effect backdrop, and that backdrop, the title, traffic lights, compact draggable OSC and pointer share one interruptible fade state restored by video pointer movement. The transparent top drag hit region remains active while its visual chrome is hidden, while AppKit mouse-button handling may reapply cursor hiding only when the OSC is still hidden. The base player-window minimum is 285×120, matching IINA; the effective minimum follows the active video ratio, and the OSC uses one responsive width for rendering, drag bounds, hit testing and scroll exclusion while narrow densities retain playback and the seek timeline and remove secondary controls. Each windowed live-resize gesture freezes its initial frame, effective video ratio, visible study-sidebar width and width/height driver, and derives every proposed frame from that immutable snapshot; it never installs a persistent AppKit aspect constraint. Native full-screen transitions bypass frame, aspect and chrome animation. Player exit, app deactivation, popup/inspector/sidebar presentation, full-screen transitions and teardown must explicitly restore the cursor; single-click remains play/pause, double-click remains fullscreen, and inspector/mining history keep their separate overlay/sidebar roles. Default subtitle placement must clear the default OSC position; dragging the OSC is an adjustment affordance, not a requirement for reading captions.
- Keep subtitle appearance and masking on the visible TextKit layout used for lookup. Default ASS text shares the user's font, size, edges and position; Respect ASS Styles overrides those values with supported authored styling and positions. Do not add transparent hit surfaces over libass-rendered text.
- Reuse shared lookup, popup, nested lookup, word audio, AnkiConnect and duplicate-check behavior.
- Keep Video shortcut browsing and editing in the unified Keyboard Shortcuts and Game Controller surfaces under Shortcuts & Controls. Both input surfaces consume the same application shortcut registry, scope-aware handler pipeline and action identifiers, so Video Settings must not duplicate the shortcut inventory, navigation entry, recorder, dispatch logic or store. Controller bindings use their own action-id configuration and preserve the legacy Reader/Sasayaki defaults through migration.
- Carry video-only mining data through `MiningContext.video`; do not make EPUB models depend on video playback state. Video media capture stays on this path: subtitle mining may capture the current frame and bundled-libmpv subtitle-range audio, but normal AnkiConnect field mappings still decide whether `{video-screenshot}` and `{video-audio-clip}` become note attachments. Required mapped audio failure must stop the note before submission.
- Keep Video Mining History video-only for now: it is a bounded, chronological subtitle capture queue independent of Anki results. Continuing from history must reopen the saved media/subtitle context and return to the shared Video lookup/Popup path rather than adding a second card editor or Anki client.
- Keep secondary/bilingual subtitles, arbitrary positioned-ASS glyph hit geometry, viewing statistics and sync as later phases.

## AnkiConnect

Long-term direction:

- Keep AnkiConnect as the Mac mining path.
- Separate connection state, deck/model fetching, field mapping, and note creation enough that each can fail with clear UI state.
- Preserve existing mappings when refreshing decks and models.
- Keep known note-type defaults in the Anki model boundary and let `AnkiManager` merge only missing current-model fields during load, refresh, and model selection; explicit user mappings remain authoritative. A separately confirmed settings action may overwrite only fields defined by the selected known template while preserving other available fields.
- Keep AnkiConnect URL, timeout, reconnect, sync options and server metadata global; deck, model, mappings, tags, duplicate/media and glossary choices are selected by explicit Profile ID.

## Local Audio And Sasayaki

Long-term direction:

- Keep dictionary word audio and Sasayaki whole-book audio as separate services.
- Keep Sasayaki matching logic and sidecar persistence in the existing Bookshelf/Sasayaki service boundary; the native Bookshelf owns only the selected-book state and match-sheet presentation.
- Make fallback behavior explicit and visible in code, not implicit through shared player utilities.
- Keep `LocalFileServer` ownership narrow: serving local assets, not deciding audio semantics.

## Google Drive Sync

Long-term direction:

- Model sync as user-progress protection, not just file upload/download.
- Preserve timestamps and sidecar metadata carefully when progress does not numerically change.
- Make conflict behavior auditable before changing token, actor, or callback flows.

## Release

Long-term direction:

- Keep `main` as the release branch.
- Keep DMG and checksum as primary release artifacts.
- Publish one full-feature DMG and checksum. A release is complete only when the full-build bundle contract passes.
- Keep release notes user-facing and Chinese-first unless the user requests otherwise.

## Build And Runtime Identity

- Treat `moe.shishamo.hoshi` as the only active bundle identity. Google Drive credentials live in one account-only Keychain item (`googleDriveCredentials`), and render-time auth state must use cached/presence checks instead of reading token secret data. Legacy split accounts (`accessToken`, `refreshToken`, `clientId`) are migration inputs only when a real sync/auth operation needs credentials. Do not add a Mac-only Google Drive service namespace unless a future migration plan handles Keychain prompts and token continuity explicitly.
- Treat the bundle-id change as a persistence migration boundary: file-based Application Support compatibility does not imply `UserDefaults.standard` continuity. Any legacy defaults import must be explicit, one-time, known-key-only, and must never overwrite values already present in the current domain.
- Resolve local UI validation from the exact Xcode build product, then verify both its `CFBundleIdentifier` and the running process executable path.
- Do not use process name, window title, or an unqualified app name as runtime identity; an old `/Applications/Niratan.app` can share all three while running obsolete code.
