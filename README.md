Rom Inspector for Trimui Brick (NextUI)

Rom Inspector is a shell script designed for retro gaming enthusiasts to manage and audit ROM libraries on the TrimUI Brick running NextUI. It scans ROM folders to generate detailed reports on missing cover art, duplicate ROMs, file sizes, orphaned files, and library statistics, helping you keep your game collection organized.

Features

List Missing Covers: Identifies ROMs without cover art and generates a report (missing_covers.txt). Supports .media (NextUI).
Remove Duplicate ROMs: Detects and allows deletion of duplicate ROMs based on filenames (excluding extensions), logging actions in duplicate_roms_removed.txt.
Check ROM Sizes: Identifies ROMs that are too small or too large based on system-specific thresholds, with a report saved to rom_sizes_report.txt. Allows deletion of problematic ROMs.
List Orphaned Files: Detects files in ROM directories that don't match valid system extensions, saving results to orphaned_files.txt.
Verify Cover Resolutions: Checks cover art resolutions for device compatibility (requires implementation of verify_cover_resolutions function), with results in cover_resolutions_report.txt.
Statistics: Provides insights into your ROM library, including:
Total ROMs per system.
Percentage of ROMs with covers per system and overall.
Disk usage analysis per system.
Comprehensive report saved to statistics_report.txt.


Logging: Detailed logs are saved to /mnt/SDCARD/.userdata/tg5040/logs/Rom Inspector.txt for debugging and tracking.

Rom Inspector scans ROMs in /mnt/SDCARD/Roms/<System> and their cover images in /mnt/SDCARD/Roms/<System>/.media. 
Supported extensions include:
.nes, .sfc, .smc, .gba, .gb, .gbc, .zip, .bin, .iso, .img, .smd, .md, .sms, .gg, .32x, .a26, .a78, .lnx, .ws, .wsc, .min, .adf, .dsk, .col, .d64, .t64, .tap, .prg, .exe, .wad, .mgw, .7z, .chd, and more.

See the get_valid_extensions function in the script for the full list per system.
Output Example
Example output for missing_covers.txt:
System: GBA
With Covers: 187 / 195
Missing: 8
ROMs without cover:
* SonicAdvance2.gba
* MetroidZeroMission.gba

System: NES
With Covers: 5 / 7
Missing: 2
ROMs without cover:
* Contra.nes
* NinjaGaiden.nes

========================================================
OVERALL SUMMARY:
Total ROMs: 500
With Covers: 478
Without Covers: 22
Scan completed on: Mon Jun 30 2025 07:20

Other reports include:

duplicate_roms_removed.txt: Logs deleted duplicate ROMs.
rom_sizes_report.txt: Lists ROMs with suspicious sizes.
orphaned_files.txt: Lists non-ROM files in ROM directories.
statistics_report.txt: Summarizes ROM counts, cover percentages, and disk usage.
cover_resolutions_report.txt: Lists covers with incorrect resolutions.

Installation & Usage
Prerequisites

Device: TrimUI Brick running NextUI V5.5.1 (not tested on Trimui Smart Pro).
Dependencies: Requires minui-list for menu navigation and jq for parsing menu outputs.
Storage: SD card with ROMs in /mnt/SDCARD/Roms/<System> and covers in /mnt/SDCARD/Roms/<System>/.media.

Installation

Copy the Script:

Place the .pak file in /mnt/SDCARD/Tools/tg5040/Rom Inspector.pak.
Ensure the script (launch.sh) is inside /mnt/SDCARD/Tools/tg5040/Rom Inspector.pak/


Set Permissions:
chmod +x /mnt/SDCARD/Tools/tg5040/RomInspector/Rom Inspector.sh


Create Directories:
mkdir -p /mnt/SDCARD/.userdata/tg5040/Tools/tg5040/Artworks Checker
mkdir -p /mnt/SDCARD/.userdata/tg5040/logs


Add Binaries (if needed):

Place additional binaries (e.g., minui-list, jq) in /mnt/SDCARD/Tools/tg5040/RomInspector/bin/arm or bin/arm64.


Usage

Run the Script:

Via terminal:cd /mnt/SDCARD/Tools/tg5040/RomInspector
./launch.sh


Or launch via the NextUI menu by selecting Rom Inspector.pak.


Navigate the Menu:

Use device controls to select options:
Check ROM sizes
Remove duplicate ROMs
List missing covers
List orphaned files
Verify cover resolutions
Statistics
Exit


Press "BACK" to return or "EXIT" to quit.


Review Outputs:

Reports are saved in /mnt/SDCARD/ (e.g., missing_covers.txt, rom_sizes_report.txt).
Logs are saved in /mnt/SDCARD/.userdata/tg5040/logs/Rom Inspector.txt.


Directory Structure

ROMs: /mnt/SDCARD/Roms/<System> (e.g., /mnt/SDCARD/Roms/GBA).
Covers: /mnt/SDCARD/Roms/<System>/.media or .res (e.g., /mnt/SDCARD/Roms/GBA/.media/Mario.png).
Cache: Temporary files in /mnt/SDCARD/Roms/<System>/.cache (e.g., missing_covers.txt, orphaned_files.txt).
Logs: /mnt/SDCARD/.userdata/tg5040/logs/Rom Inspector.txt.
Temporary Files: Menu files (e.g., /tmp/roms_missing.menu) are cleaned up on exit.

Notes

Safety: No files are modified or deleted without user confirmation.
Performance: Limits processing to 1000 files per system to prevent overload. For Sony PlayStation, detailed scans skip if ROM count exceeds 50.
NextUI Detection: Uses .media or .res based on the IS_NEXT variable or presence of minuisettings.txt.
Limitations:
The verify_cover_resolutions function requires additional implementation.
Designed for NextUI; compatibility with other firmwares may vary.


Dependencies: Relies on BusyBox core utils, minui-list, and jq, which are lightweight and typically included in custom firmwares and pak.

Credits
Created with passion by Gabrielpsp for the retro gaming community. Designed for TrimUI Brick running NextUI OS.
