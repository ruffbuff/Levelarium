# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-10-28

### Added
- Undo / redo: `Ctrl+Z`, `Ctrl+Y` or `Ctrl+Shift+Z`. One action = one step (a whole brush stroke, fill,
  line, rectangle or eraser stroke). History depth is 100 and it is reset when a level is loaded or
  created, a layer is deleted or the canvas is resized. New module `scripts/history.lua`.
- Atomic saving (`scripts/fileio.lua`): the file is written to a temporary file and renamed, so a failed save
  never corrupts the previous version; write errors are shown as a toast.
- TXT files now store the asset pack and tile size in the header (`w,h,layers,pack,tileSize`); opening such a
  file restores the pack. Old files and old readers keep working (the first three numbers are unchanged).
- TMX export copies the used tile images next to the `.tmx` (`tiles/<pack>/N.png`).
- `O` in the Open screen opens the levels folder.
- `packaging/`: build scripts for the `.love` file, a Windows x64 zip, an NSIS installer and a Linux AppImage
  (`packaging/build.sh`).

### Fixed
- TMX: correct relative tile paths and `tilewidth`/`tileheight` equal to the real PNG size (32).
- `Ctrl+S` no longer pans the camera (`S` of WASD).
- Fast mouse strokes no longer leave gaps (positions between mouse events are interpolated).
- Bucket fill is iterative (scanline), so large areas no longer hit the recursion limit or freeze.
- Windows reserved file names (`CON`, `NUL`, ...) are rejected as level names; the unsaved mark is set when the
  asset pack is switched; debug output removed from the console.

### Changed
- `tileSize` in JSON/TMX is now the real PNG size (32) instead of the editor display size (64).

## [1.2.0] - 2026-10-28

### Added
- Main menu: Continue (only when a level is open), New level, Open level, Quit; keyboard
  (arrows/Enter/Esc) and mouse navigation, version in the title, key hints.
- `Esc` in the editor returns to the menu without losing unsaved work; New level asks for
  confirmation when there are unsaved changes.
- Save screen: name input, TXT/JSON/TMX format buttons, list of existing files with overwrite
  confirmation. Open screen: scrolling list (wheel, arrows, PgUp/PgDn, Home/End) with date and size,
  sorted by date or name (`Tab`).
- Toast notifications for success and errors (instead of console output); the asset pack list scrolls.
- Unsaved-changes indicator (`*`) in the HUD and window title, updated hotkey hints.
- `Ctrl+S` quick save.
- Update check at startup: a background `curl` request (in a `love.thread`) to GitHub releases;
  shows "Version X is available" in the menu (click or `U` opens the release page). Silent on any
  failure, `checkUpdates = false` in `scripts/settings.lua` turns it off; `LEVELARIUM_UPDATE_URL` and
  `LEVELARIUM_TEST_VERSION` environment variables override the address/version for testing.
- New small modules `scripts/ui.lua`, `list.lua`, `files.lua`, `version.lua`, `updater.lua` and tests for
  their logic (version comparison, file sorting/formatting, list scrolling, release parsing).

### Changed
- `conf.lua` moved from `scripts/` to the project root: LÖVE reads it only there, so before the window
  settings, title and icon from that file were never applied. Packaged builds (`.love`) must contain
  the root `conf.lua`. The game identity is now `Levelarium`, so in a packaged build the save
  directory is the one for that identity.
- The interface text is English (the default font has no Cyrillic glyphs).
- `scripts/main.lua` is organised around screens (menu, editor, modal dialogs) instead of ad-hoc flags.

### Fixed
- The key that confirmed or opened a dialog (`Y`/`N`, `P`, `L`) could end up in a text field.
- Closing the window with unsaved changes silently discarded them; it now asks first.

## [1.1.0] - 2026-10-28

### Added
- Eyedropper: right click on the grid picks the tile under the cursor (current layer first,
  then the upper layers) and switches to the brush; the palette scrolls to the picked tile.
- `scripts/level.lua`: the pure level logic (TXT/JSON/TMX serialisation, TXT parsing, flood fill,
  line rasterisation, canvas trimming) moved out of `main.lua`, with no dependency on `love.*`.
- Tests for that logic: `lua tests/run.lua`.
- `CHANGELOG.md`.
- Maximum grid size (`maxGridSize` in `scripts/settings.lua`, 1000).

### Changed
- Level files are written and listed without `mkdir -p` / `ls` shell commands, so saving and
  loading work on Windows as well. In a packaged build levels go to the LÖVE save directory.
- Saving large levels is much faster (`table.concat` instead of string concatenation in loops).
- README: documented all hotkeys, the in-editor grid size dialog, the formats and the tests.

### Fixed
- Resizing the canvas to a smaller size did not remove tiles outside of it (the loop compared the new
  width with itself); the canvas dialog also showed stale values after loading a level.
- Bucket fill used recursion and crashed with `stack overflow` on large empty areas (100x100 and up).
- The key that opened the save dialog (`P`) ended up in the level name input.
- Clicking the left margin of the tile palette selected "tile 0"; clicks on the right edge or below the
  last row selected tiles from other rows.
- Dragging the brush/eraser over the tools panel or the palette painted tiles hidden under them.
- Right and middle mouse buttons painted like the left one, and releasing them finished line/rectangle.
- TMX export described the whole tileset as one 512x512 sprite sheet (`1.png`, 64 tiles hard-coded);
  now every tile image is a separate tile of an image-collection tileset.
- Loading a level crashed on an empty or corrupted TXT file and did not work with `\r\n` line endings.
- Entering a huge canvas size (e.g. 99999999) froze the editor; size is limited to 1000.
- Switching asset packs could leave the selected tile at 0 or the palette scrolled past the end.
- Level names consisting only of spaces are no longer accepted.
