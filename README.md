# ROM-INSPECTOR.PAK

## 🕹️ ROM Inspector

ROM Inspector is a shell script designed for the TrimUI Brick running NextUI, enabling you to efficiently manage and analyze your ROM collections and artwork.

**Version 1.0.0 — first stable release.** ROM Inspector has moved out of beta: a critical startup bug that prevented the pak from launching on NextUI has been fixed, and a trash-based safety net now protects against accidental deletions (see the [changelog](changelog.txt) for details).

This release provides a set of tools to optimize your SD card file organization by identifying and resolving common issues with ROMs and covers.

## ✨ Key Features

- **✅ ROM Size Verification** — Identifies ROMs with suspicious sizes (too small or too large) based on system-specific thresholds, with an option to delete after confirmation.
- **♻️ Duplicate ROM Removal** — Detects and allows you to remove duplicate ROMs per system to save space.
- **📄 Missing Covers List** — Scans for ROMs without corresponding cover images and generates a detailed report.
- **🗑️ Orphaned Files Detection** — Finds cover images without matching ROMs, with an option to delete.
- **🖼️ Cover Resolution Check** — Identifies covers with incorrect resolutions (e.g., not 480x480 or too low), with an option to delete.
- **📊 Detailed Statistics** — Generates reports on ROM counts per system, cover usage percentage, and disk usage (ROMs and covers).
- **📝 ROM Name Validation** — Checks ROM names for invalid characters and formatting issues, generates a report, and offers options to auto-rename or delete problematic files.
- **📦 ZIP ROM Management** — Scans ZIP ROM files, lets you decompress, delete, or skip them, and generates a detailed report with progress feedback.
- **🗑️ Trash / Safety Net (New in 1.0.0)** — Deleted files (ROMs, covers, orphaned files, ZIPs) are moved to a dedicated Trash folder instead of being permanently erased. A new "Manage Trash" menu shows how much space it's using and lets you empty it once you're confident you no longer need those files.

## ⚙️ Technical Details

- **Compatibility:** Optimized for TrimUI Brick with NextUI, supports `.media` folders.
- **Interface:** Uses `minui-list` for intuitive menu navigation.
- **🗄️ Logs:** Detailed logs saved in `/mnt/SDCARD/.userdata/tg5040/logs/Rom Inspector.txt` for debugging and tracking.
- **Exported Reports:** Generates text files (e.g., `missing_covers.txt`, `rom_sizes_report.txt`) saved in `/mnt/SDCARD/` for offline analysis.
- **Safety:** User confirmation required before any file is moved to trash, and again before the trash is permanently emptied.
- **Performance:** Limits processing to 1000 files per system to prevent overload.

## 💾 Installation

1️⃣ Extract the contents of the compressed file `Rom Inspector.pak.zip` to:
`/mnt/SDCARD/Tools/tg5040/`
It should be: `/mnt/SDCARD/Tools/tg5040/Rom Inspector.pak`

2️⃣ Make sure the following files are available in:
- `/mnt/SDCARD/.userdata/tg5040/Rom Inspector.pak/bin`
- `/mnt/SDCARD/.userdata/tg5040/Rom Inspector.pak/lib`

3️⃣ Insert your SD card back into the TrimUI Brick.

4️⃣ Access the Tools section in NextUI, then select Rom Inspector from the menu to launch it.

## ⚠️ Notes

- ROM size thresholds and expected cover resolutions are predefined but can be adjusted.
- Compatibility with all emulated systems is not yet fully tested.
- Deleted files are moved to a Trash folder rather than erased immediately — remember to empty it from the "Manage Trash" menu once you're sure you don't need those files, to actually free up SD card space.
- Feedback and bug reports are very welcome via GitHub issues!

## 🚀 Usage Examples

Launch the script to access the main menu, where you can:

- ✅ Check ROM sizes to find suspicious files.
- ♻️ Remove duplicates to free up space.
- 📝 Generate reports to help plan adding missing covers.
- 🗑️ Review and empty the trash once you're happy with the changes you've made.

## 📌 Prerequisites

- TrimUI Brick running NextUI.
- TF Card with a standard `/mnt/SDCARD/Roms` directory structure.
- Tools installed: `minui-list`, `jq`, `identify` from the .pak.

## 🔮 Future Plans

- Hash-based duplicate detection (to catch renamed duplicates and avoid false positives between regional variants).
- Multi-disc (`.m3u`/`.cue`) awareness to avoid false positives in size and orphaned-file checks.
- Optional cover download/resize (would require bundling additional tools such as `curl`/`convert`).
- Configurable size thresholds and expected resolutions via an external config file.
- Enhanced compatibility with additional systems and formats.
- Performance improvements for large collections.
- Other tools and bug fixes.

## 🤝 Contribute

Fork, test, and share your suggestions to help ROM Inspector evolve! All contributions are welcome!
