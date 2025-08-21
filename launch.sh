#!/bin/sh
# Initialize critical variables with defaults
[ -z "$USERDATA_PATH" ] && USERDATA_PATH="/mnt/SDCARD/.userdata/tg5040"
[ -z "$LOGS_PATH" ] && LOGS_PATH="/mnt/SDCARD/.userdata/tg5040/logs"
PAK_DIR="$(dirname "$0")"
CACHE_FILE="$USERDATA_PATH/Tools/tg5040/Artworks Checker/platforms.cache"
EXPORT_FILE="/mnt/SDCARD/missing_covers.txt"
STATS_FILE="/mnt/SDCARD/statistics_report.txt"
ROM_SIZES_FILE="/mnt/SDCARD/rom_sizes_report.txt"
ORPHANED_FILES_FILE="/mnt/SDCARD/orphaned_files.txt"
DISK_USAGE_FILE="/mnt/SDCARD/disk_usage_report.txt"
ROM_NAMES_FILE="/mnt/SDCARD/rom_names_report.txt"
ZIP_ROMS_FILE="/mnt/SDCARD/zip_roms_report.txt"

# Reduced logging: Only log critical initialization details
echo "Initializing: USERDATA_PATH=$USERDATA_PATH, LOGS_PATH=$LOGS_PATH, PAK_DIR=$PAK_DIR, CACHE_FILE=$CACHE_FILE, EXPORT_FILE=$EXPORT_FILE, STATS_FILE=$STATS_FILE, ROM_SIZES_FILE=$ROM_SIZES_FILE, ORPHANED_FILES_FILE=$ORPHANED_FILES_FILE, ROM_NAMES_FILE=$ROM_NAMES_FILE, ZIP_ROMS_FILE=$ZIP_ROMS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"

# Verify PAK_DIR exists
if [ ! -d "$PAK_DIR" ]; then
    echo "Error: PAK_DIR ($PAK_DIR) does not exist or is not a directory." >> "$LOGS_PATH/Rom Inspector.txt"
    exit 1
fi

# Create necessary directories
mkdir -p "$USERDATA_PATH/Tools/tg5040/Artworks Checker" 2>/dev/null || {
    echo "Error: Failed to create directory $USERDATA_PATH/Tools/tg5040/Artworks Checker" >> "$LOGS_PATH/Rom Inspector.txt"
    exit 1
}
mkdir -p "$LOGS_PATH" 2>/dev/null || {
    echo "Error: Failed to create directory $LOGS_PATH" >> "$LOGS_PATH/Rom Inspector.txt"
    exit 1
}

# Clear old log
rm -f "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null
exec >>"$LOGS_PATH/Rom Inspector.txt" 2>&1
echo "=== Starting Rom Inspector ==="

# Check if /mnt/SDCARD/Roms is accessible
if [ ! -d "/mnt/SDCARD/Roms" ] || [ ! -r "/mnt/SDCARD/Roms" ]; then
    echo "Error: /mnt/SDCARD/Roms does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Error: ROMs directory not found or not readable." 5
    exit 1
fi

# Clear cache at startup to ensure fresh menu
if [ -f "$CACHE_FILE" ]; then
    rm -f "$CACHE_FILE" 2>/dev/null && echo "Deleted cache file at startup: $CACHE_FILE" || echo "Error: Failed to delete cache file at startup: $CACHE_FILE"
else
    echo "No cache file found at startup: $CACHE_FILE"
fi

# Change to script directory
cd "$PAK_DIR" || {
    echo "Error: Failed to change directory to $PAK_DIR"
    exit 1
}

ARCH=arm
[ "$(uname -m)" = "aarch64" ] && ARCH=arm64

export PATH="$PAK_DIR/bin/$ARCH:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$PAK_DIR/lib/$ARCH:$PAK_DIR/lib/$PLATFORM:$PAK_DIR/lib:$LD_LIBRARY_PATH"

show_message() {
    msg="$1"
    secs="${2:-forever}"
    killall minui-presenter >/dev/null 2>&1 || true
    if [ "$secs" = "forever" ]; then
        minui-presenter --message "$msg" --timeout 9999 2>/dev/null &
        echo "$!" > /tmp/loading_pid
    else
        minui-presenter --message "$msg" --timeout "$secs" 2>/dev/null
    fi
}

stop_loading() {
    if [ -f /tmp/loading_pid ]; then
        kill $(cat /tmp/loading_pid) 2>/dev/null || true
        rm -f /tmp/loading_pid 2>/dev/null
    fi
}

cleanup() {
    if [ -f "$CACHE_FILE" ]; then
        rm -f "$CACHE_FILE" 2>/dev/null && echo "Deleted cache file on exit: $CACHE_FILE" || echo "Error: Failed to delete cache file on exit: $CACHE_FILE"
    else
        echo "No cache file found on exit: $CACHE_FILE"
    fi
    rm -f /tmp/stay_awake /tmp/platforms.menu /tmp/main_menu.menu /tmp/minui-output /tmp/roms_missing.menu /tmp/roms_missing_temp.menu /tmp/duplicates.menu /tmp/roms_duplicates.menu /tmp/rom_files.menu /tmp/rom_names.txt /tmp/rom_names_only.txt /tmp/statistics.menu /tmp/total_roms.menu /tmp/covers_percentage.menu /tmp/rom_sizes.menu /tmp/rom_sizes_temp.menu /tmp/roms_orphaned.menu /tmp/systems_zip.menu /tmp/roms_zip.menu /tmp/zip_action.menu /tmp/keep_zip.menu /tmp/loading_pid /tmp/rom_list.menu 2>/dev/null
    echo "Cleaned up temporary files."
}
trap cleanup EXIT INT TERM HUP QUIT

# Helper function for deletion confirmation
confirm_deletion() {
    local file_to_delete="$1"
    local file_type="$2"  # e.g., "ROM", "orphaned file", "cover"
    local confirm_menu="/tmp/confirm_deletion.menu"
    
    # Clear previous minui-output to avoid stale data
    rm -f /tmp/minui-output 2>/dev/null
    
    # Create confirmation menu
    > "$confirm_menu"
    echo "Yes" >> "$confirm_menu"
    echo "No" >> "$confirm_menu"

    echo "Confirm deletion menu contents for $file_to_delete:" >> "$LOGS_PATH/Rom Inspector.txt"
    cat "$confirm_menu" >> "$LOGS_PATH/Rom Inspector.txt"

    minui-list --disable-auto-sleep \
        --item-key confirm_deletion \
        --file "$confirm_menu" \
        --format text \
        --cancel-text "CANCEL" \
        --title "Confirm Deletion of $file_type: ${file_to_delete##*/}" \
        --write-location /tmp/minui-output \
        --write-value state
    MINUI_EXIT_CODE=$?

    echo "minui-list exit code for confirm_deletion: $MINUI_EXIT_CODE" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "minui-output contents:" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/minui-output 2>/dev/null >> "$LOGS_PATH/Rom Inspector.txt" || echo "No minui-output file found" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
        echo "User cancelled deletion of $file_to_delete (exit code: $MINUI_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
        rm -f "$confirm_menu" 2>/dev/null
        return 1
    fi

    if [ ! -f /tmp/minui-output ]; then
        echo "Error: /tmp/minui-output not found after minui-list" >> "$LOGS_PATH/Rom Inspector.txt"
        rm -f "$confirm_menu" 2>/dev/null
        return 1
    fi

    idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
    echo "Selected index for confirm_deletion: $idx" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ -z "$idx" ] || [ "$idx" = "null" ] || [ "$idx" = "-1" ] || [ "$idx" != "0" ]; then
        echo "Deletion of $file_to_delete not confirmed (index: $idx)" >> "$LOGS_PATH/Rom Inspector.txt"
        rm -f "$confirm_menu" 2>/dev/null
        return 1
    fi

    echo "Deletion confirmed for $file_to_delete" >> "$LOGS_PATH/Rom Inspector.txt"
    rm -f "$confirm_menu" 2>/dev/null
    return 0
}

# Define valid extensions per system
get_valid_extensions() {
    SYS_NAME="$1"
    case "$SYS_NAME" in
        "Game Boy (GB)"|"Super Game Boy (SGB)"|"GB")
            echo "gb zip"
            ;;
        "Game Boy Color (GBC)"|"GBC")
            echo "gbc zip gb"
            ;;
        "Game Boy Advance (GBA)"|"Game Boy Advance (MGBA)"|"GBA"|"MGBA")
            echo "gba zip"
            ;;
        "Nintendo Entertainment System (FC)"|"Famicom Disk System (FDS)"|"FC"|"FDS")
            echo "nes zip"
            ;;
        "Super Nintendo Entertainment System (SFC)"|"Super Nintendo Entertainment System (SUPA)"|"SFC"|"SUPA")
            echo "sfc smc zip"
            ;;
        "Sega Genesis (MD)"|"Sega Megadrive (MD)"|"MD")
            echo "md smd gen bin zip"
            ;;
        "Sony PlayStation (PS)"|"PS")
            echo "bin iso img zip chd cue"
            ;;
        "PC Engine (PCE)"|"TurboGrafx-16 (PCE)"|"Super Grafx (SGFX)"|"TurboGrafx-CD (PCECD)"|"PCE"|"SGFX"|"PCECD")
            echo "pce zip"
            ;;
        "Sega Master System (SMS)"|"SMS")
            echo "sms zip"
            ;;
        "Sega Game Gear (GG)"|"GG")
            echo "gg zip"
            ;;
        "Sega 32X (32X)"|"Sega 32X (THIRTYTWOX)"|"32X"|"THIRTYTWOX")
            echo "32x zip"
            ;;
        "Atari 2600 (ATARI)"|"ATARI")
            echo "a26 zip"
            ;;
        "Atari 5200 (FIFTYTWOHUNDRED)"|"FIFTYTWOHUNDRED")
            echo "a78 zip"
            ;;
        "Atari Lynx (LYNX)"|"LYNX")
            echo "lnx zip"
            ;;
        "Wonder Swan Color (WSC)"|"Wonderswan Color (WSC)"|"WSC")
            echo "ws wsc zip"
            ;;
        "Pokemon mini (PKM)"|"Pokémon mini (PKM)"|"PKM")
            echo "min zip"
            ;;
        "ARCADE"|"Arcade (FBN)"|"MAME (FBN)")
            echo "zip"
            ;;
        "PORTS"|"Ports (PORTS)")
            echo "zip sh"
            ;;
        "Amiga (AMIGA)"|"Amiga (PUAE)")
            echo "adf zip"
            ;;
        "Amstrad CPC (CPC)"|"Armstrad CPC (CPC)")
            echo "dsk zip"
            ;;
        "Colecovision (COLECO)")
            echo "col zip"
            ;;
        "Commodore 128 (C128)"|"Commodore 64 (C64)"|"Commodore 64 (COMMODORE)"|"Commodore PET (PET)"|"Commodore Plus4 (PLUS4)"|"Commodore VIC20 (VIC)")
            echo "d64 t64 tap prg zip"
            ;;
        "DOS (DOS)")
            echo "exe zip"
            ;;
        "Doom (DOOM)"|"Doom (PRBOOM)")
            echo "wad zip"
            ;;
        "EasyRPG (EASYRPG)")
            echo "zip"
            ;;
        "Game & Watch (GW)")
            echo "mgw zip"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Define size thresholds per system (in bytes)
get_size_thresholds() {
    SYS_NAME="$1"
    case "$SYS_NAME" in
        "Game Boy (GB)"|"Super Game Boy (SGB)"|"GB")
            echo "1000 6000000" # < 6KB suspicious, > 6MB large
            ;;
        "Game Boy Color (GBC)"|"GBC")
            echo "1000 9000000" # < 192KB suspicious, > 9MB large
            ;;
        "Game Boy Advance (GBA)"|"Game Boy Advance (MGBA)"|"GBA"|"MGBA")
            echo "1000 65000000" # < 256KB suspicious, > 65MB large
            ;;
        "Nintendo Entertainment System (FC)"|"Famicom Disk System (FDS)"|"FC"|"FDS")
            echo "1000 1000000" # < 6KB suspicious, > 1MB large
            ;;
        "Super Nintendo Entertainment System (SFC)"|"Super Nintendo Entertainment System (SUPA)"|"SFC"|"SUPA")
            echo "1000 6000000" # < 192KB suspicious, > 6MB large
            ;;
        "Sega Genesis (MD)"|"Sega Megadrive (MD)"|"MD")
            echo "1000 8000000" # < 64KB suspicious, > 8MB large
            ;;
        "Sony PlayStation (PS)"|"PS")
            echo "1000 700000000" # < 500KB suspicious, > 999MB large
            ;;
        "PC Engine (PCE)"|"TurboGrafx-16 (PCE)"|"Super Grafx (SGFX)"|"TurboGrafx-CD (PCECD)"|"PCE"|"SGFX"|"PCECD")
            echo "1000 10000000" # < 6KB suspicious, > 10MB large
            ;;
        "Sega Master System (SMS)"|"SMS")
            echo "1000 1000000" # < 16KB suspicious, > 1MB large
            ;;
        "Sega Game Gear (GG)"|"GG")
            echo "1000 1000000" # < 16KB suspicious, > 1MB large
            ;;
        "Sega 32X (32X)"|"Sega 32X (THIRTYTWOX)"|"32X"|"THIRTYTWOX")
            echo "1000 4000000" # < 8KB suspicious, > 4MB large
            ;;
        "Atari 2600 (ATARI)"|"ATARI")
            echo "1000 50000" # < 1KB suspicious, > 50KB large
            ;;
        "Atari 5200 (FIFTYTWOHUNDRED)"|"FIFTYTWOHUNDRED")
            echo "1000 100000" # < 1KB suspicious, > 100KB large
            ;;
        "Atari Lynx (LYNX)"|"LYNX")
            echo "1000 2000000" # < 16KB suspicious, > 2MB large
            ;;
        "Wonderswan Color (WSC)"|"Wonder Swan Color (WSC)"|"WSC")
            echo "1000 4000000" # < 16KB suspicious, > 4MB large
            ;;
        "Pokemon mini (PKM)"|"Pokémon mini (PKM)"|"PKM")
            echo "1000 4000000" # < 1KB suspicious, > 4MB large
            ;;
        "ARCADE"|"Arcade (FBN)"|"MAME (FBN)")
            echo "1000 50000000" # < 1KB suspicious, > 50MB large
            ;;
        "PORTS"|"Ports (PORTS)")
            echo "1000 100000000" # < 1KB suspicious, > 999MB large
            ;;
        "Amiga (AMIGA)"|"Amiga (PUAE)")
            echo "1000 4000000" # < 16KB suspicious, > 4MB large
            ;;
        "Amstrad CPC (CPC)"|"Armstrad CPC (CPC)")
            echo "1000 4000000" # < 16KB suspicious, > 4MB large
            ;;
        "Colecovision (COLECO)")
            echo "1000 1000000" # < 1KB suspicious, > 1MB large
            ;;
        "Commodore 128 (C128)"|"Commodore 64 (C64)"|"Commodore 64 (COMMODORE)"|"Commodore PET (PET)"|"Commodore Plus4 (PLUS4)"|"Commodore VIC20 (VIC)")
            echo "1000 1000000" # < 1KB suspicious, > 1MB large
            ;;
        "DOS (DOS)")
            echo "1000 100000000" # < 1KB suspicious, > 700MB large
            ;;
        "Doom (DOOM)"|"Doom (PRBOOM)")
            echo "1000 100000000" # < 1KB suspicious, > 700MB large
            ;;
        "EasyRPG (EASYRPG)")
            echo "1000 100000000" # < 1KB suspicious, > 999MB large
            ;;
        "Game & Watch (GW)")
            echo "1000 1000000" # < 1KB suspicious, > 1MB large
            ;;
        *)
            echo "1000 100000000" # Default: < 1KB suspicious, > 100MB large
            ;;
    esac
}

# Define minimum cover resolution per system (width and height in pixels)
get_min_cover_resolution() {
    SYS_NAME="$1"
    case "$SYS_NAME" in
        "Game Boy (GB)"|"Super Game Boy (SGB)"|"GB")
            echo "254" # Minimum 254x254 for Game Boy
            ;;
        "Game Boy Color (GBC)"|"GBC")
            echo "254" # Minimum 254x254 for Game Boy Color
            ;;
        "Game Boy Advance (GBA)"|"Game Boy Advance (MGBA)"|"GBA"|"MGBA")
            echo "480" # Minimum 480x480 for GBA
            ;;
        "Nintendo Entertainment System (FC)"|"Famicom Disk System (FDS)"|"FC"|"FDS")
            echo "320" # Minimum 320x320 for NES/FDS
            ;;
        "Super Nintendo Entertainment System (SFC)"|"Super Nintendo Entertainment System (SUPA)"|"SFC"|"SUPA")
            echo "480" # Minimum 480x480 for SNES
            ;;
        "Sega Genesis (MD)"|"Sega Megadrive (MD)"|"MD")
            echo "480" # Minimum 480x480 for Genesis
            ;;
        "Sony PlayStation (PS)"|"PS")
            echo "640" # Minimum 640x640 for PlayStation
            ;;
        "PC Engine (PCE)"|"TurboGrafx-16 (PCE)"|"Super Grafx (SGFX)"|"TurboGrafx-CD (PCECD)"|"PCE"|"SGFX"|"PCECD")
            echo "320" # Minimum 320x320 for PC Engine
            ;;
        "Sega Master System (SMS)"|"SMS")
            echo "320" # Minimum 320x320 for Master System
            ;;
        "Sega Game Gear (GG)"|"GG")
            echo "254" # Minimum 254x254 for Game Gear
            ;;
        "Sega 32X (32X)"|"Sega 32X (THIRTYTWOX)"|"32X"|"THIRTYTWOX")
            echo "480" # Minimum 480x480 for 32X
            ;;
        "Atari 2600 (ATARI)"|"ATARI")
            echo "200" # Minimum 200x200 for Atari 2600
            ;;
        "Atari 5200 (FIFTYTWOHUNDRED)"|"FIFTYTWOHUNDRED")
            echo "200" # Minimum 200x200 for Atari 5200
            ;;
        "Atari Lynx (LYNX)"|"LYNX")
            echo "254" # Minimum 254x254 for Atari Lynx
            ;;
        "Wonderswan Color (WSC)"|"Wonder Swan Color (WSC)"|"WSC")
            echo "254" # Minimum 254x254 for Wonderswan
            ;;
        "Pokemon mini (PKM)"|"Pokémon mini (PKM)"|"PKM")
            echo "200" # Minimum 200x200 for Pokemon Mini
            ;;
        "ARCADE"|"Arcade (FBN)"|"MAME (FBN)")
            echo "480" # Minimum 480x480 for Arcade
            ;;
        "PORTS"|"Ports (PORTS)")
            echo "480" # Minimum 480x480 for Ports
            ;;
        "Amiga (AMIGA)"|"Amiga (PUAE)")
            echo "480" # Minimum 480x480 for Amiga
            ;;
        "Amstrad CPC (CPC)"|"Armstrad CPC (CPC)")
            echo "320" # Minimum 320x320 for Amstrad CPC
            ;;
        "Colecovision (COLECO)")
            echo "320" # Minimum 320x320 for Colecovision
            ;;
        "Commodore 128 (C128)"|"Commodore 64 (C64)"|"Commodore 64 (COMMODORE)"|"Commodore PET (PET)"|"Commodore Plus4 (PLUS4)"|"Commodore VIC20 (VIC)")
            echo "320" # Minimum 320x320 for Commodore systems
            ;;
        "DOS (DOS)")
            echo "480" # Minimum 480x480 for DOS
            ;;
        "Doom (DOOM)"|"Doom (PRBOOM)")
            echo "480" # Minimum 480x480 for Doom
            ;;
        "EasyRPG (EASYRPG)")
            echo "480" # Minimum 480x480 for EasyRPG
            ;;
        "Game & Watch (GW)")
            echo "200" # Minimum 200x200 for Game & Watch
            ;;
        *)
            echo "480" # Default: Minimum 480x480
            ;;
    esac
}

is_valid_extension() {
    file="$1"
    valid_extensions="$2"
    [ -z "$valid_extensions" ] && return 1
    ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    for valid_ext in $valid_extensions; do
        if [ "$ext" = "$valid_ext" ]; then
            return 0
        fi
    done
    return 1
}

list_missing_covers() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="$EXPORT_FILE"
    MAX_FILES=1000  # Global limit to avoid overload

    # Determine if NextUI is used
    is_nextui=false
    image_folder=".media"
    if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
        is_nextui=true
    else
        image_folder=".res"
    fi
    echo "Using image folder: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

    show_message "Scanning for missing covers..." forever
    LOADING_PID=$!

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== Missing Covers Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create missing_covers.txt." 5
        return 1
    }

    > /tmp/roms_missing.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/roms_missing.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create menu file." 5
        return 1
    }
    VALID_SYSTEMS_FOUND=0
    TOTAL_MISSING_COUNT=0

    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || {
            echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && {
            echo "Skipping $SYS_NAME: No valid extensions defined." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }

        echo "Scanning system: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
        MEDIA_PATH="$SYS_PATH/$image_folder"
        ROM_COUNT=0
        MISSING_COUNT=0
        TEMP_FILE=$(mktemp)
        FILE_COUNT=0

        mkdir -p "$SYS_PATH/.cache" 2>/dev/null || {
            echo "Warning: Failed to create cache directory $SYS_PATH/.cache" >> "$LOGS_PATH/Rom Inspector.txt"
        }

        for ROM in "$SYS_PATH"/*; do
            [ -f "$ROM" ] && [ -r "$ROM" ] || continue
            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*|*.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                ROM_COUNT=$((ROM_COUNT + 1))
                COVER_FILE="$MEDIA_PATH/${ROM_BASENAME%.*}.png"
                if [ ! -f "$COVER_FILE" ] || [ ! -s "$COVER_FILE" ]; then
                    MISSING_COUNT=$((MISSING_COUNT + 1))
                    echo "$ROM_BASENAME" >> "$TEMP_FILE"
                    echo "Missing cover for: $ROM_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                else
                    echo "Found cover for: $ROM_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                fi
            fi
            FILE_COUNT=$((FILE_COUNT + 1))
            if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
        done

        if [ "$MISSING_COUNT" -gt 0 ]; then
            if [ "$MISSING_COUNT" -eq 1 ]; then
                echo "$SYS_NAME - $MISSING_COUNT missing cover" >> /tmp/roms_missing.menu
            else
                echo "$SYS_NAME - $MISSING_COUNT missing covers" >> /tmp/roms_missing.menu
            fi
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_MISSING_COUNT=$((TOTAL_MISSING_COUNT + MISSING_COUNT))
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            if [ "$MISSING_COUNT" -eq 1 ]; then
                echo "Missing cover: $MISSING_COUNT" >> "$OUTPUT_FILE"
            else
                echo "Missing covers: $MISSING_COUNT" >> "$OUTPUT_FILE"
            fi
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            mv "$TEMP_FILE" "$SYS_PATH/.cache/missing_covers.txt" 2>/dev/null || {
                echo "Warning: Failed to save missing covers list to $SYS_PATH/.cache/missing_covers.txt" >> "$LOGS_PATH/Rom Inspector.txt"
                rm -f "$TEMP_FILE"
            }
        else
            echo "No missing covers for $SYS_NAME (total ROMs: $ROM_COUNT)" >> "$LOGS_PATH/Rom Inspector.txt"
            rm -f "$TEMP_FILE"
        fi
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with missing covers found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No missing covers found." >> "$OUTPUT_FILE"
        show_message "No missing covers found." 5
        return 0
    fi

    echo "Systems with missing covers: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total missing covers: $TOTAL_MISSING_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/roms_missing.menu >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "Error: Failed to read /tmp/roms_missing.menu" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ ! -s /tmp/roms_missing.menu ]; then
        echo "Error: /tmp/roms_missing.menu is empty or does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to generate systems menu." 5
        return 1
    fi

    while true; do
        minui-list --disable-auto-sleep \
            --item-key missing_covers \
            --file /tmp/roms_missing.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Missing Covers" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled systems menu (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi
        if [ ! -f /tmp/minui-output ]; then
            echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Failed to read menu output." 5
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/roms_missing.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        MISSING_COVERS_FILE="$SYS_PATH/.cache/missing_covers.txt"

        if [ ! -f "$MISSING_COVERS_FILE" ] || [ ! -s "$MISSING_COVERS_FILE" ]; then
            echo "Error: Missing covers file not found or empty for $selected_sys: $MISSING_COVERS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No missing covers found for $selected_sys." 5
            continue
        fi

        show_message "Loading missing covers for $selected_sys..." forever
        LOADING_PID=$!

        minui-list --disable-auto-sleep \
            --item-key missing_cover_items \
            --file "$MISSING_COVERS_FILE" \
            --format text \
            --cancel-text "BACK" \
            --title "Missing Covers for $selected_sys" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        stop_loading

        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled ROMs menu for $selected_sys (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi
    done

    echo "Exiting list_missing_covers function" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Missing covers report saved to $OUTPUT_FILE" 5
    return 0
}

Manage_zip_roms() {
    # Create logs directory if it doesn't exist
    if [ ! -d "$LOGS_PATH" ]; then
        mkdir -p "$LOGS_PATH" 2>/dev/null || {
            echo "Error: Cannot create $LOGS_PATH" >> "$LOGS_PATH/Rom Inspector.txt"
            return 1
        }
    fi

    # Check log file permissions
    touch "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || {
        echo "Error: Cannot write to $LOGS_PATH/Rom Inspector.txt" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }

    echo "=== Checking ZIP ROMs by System ===" >> "$LOGS_PATH/Rom Inspector.txt"

    # Check dependencies
    command -v unzip >/dev/null 2>&1 || {
        echo "Error: unzip command not found" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }
    command -v minui-list >/dev/null 2>&1 || {
        echo "Error: minui-list command not found" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        echo "Error: jq command not found" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }

    # Define file paths
    systems_menu="/tmp/systems_zip.menu"
    roms_menu="/tmp/roms_zip.menu"
    zip_action_menu="/tmp/zip_action.menu"
    keep_zip_menu="/tmp/keep_zip.menu"
    zip_counts_file="/tmp/zip_counts.txt"
    cache_file="/mnt/SDCARD/zip_roms_cache.txt"
    roms_cache_dir="/mnt/SDCARD/roms_cache"
    zip_count=0
    decompressed_count=0
    deleted_count=0
    skipped_count=0
    zip_summary=""

    # Initialize report file
    touch "$ZIP_ROMS_FILE" 2>/dev/null || {
        echo "Error: Failed to create $ZIP_ROMS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }
    echo "ZIP ROMs Report - $(date)" > "$ZIP_ROMS_FILE"

    # Create action menus
    printf "Decompress ZIP\nDelete ZIP\nSkip ZIP\n" > "$zip_action_menu" 2>/dev/null || {
        echo "Error: Failed to create $zip_action_menu" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }
    printf "Keep\nDelete\n" > "$keep_zip_menu" 2>/dev/null || {
        echo "Error: Failed to create $keep_zip_menu" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }

    # Create temporary files
    : > "$systems_menu" 2>/dev/null
    : > "$zip_counts_file" 2>/dev/null || {
        echo "Error: Failed to create temporary files" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }

    # Create ROMs cache directory
    mkdir -p "$roms_cache_dir" 2>/dev/null || {
        echo "Error: Failed to create $roms_cache_dir" >> "$LOGS_PATH/Rom Inspector.txt"
        return 1
    }

    # Check if cache is valid (less than 5 minutes old)
    cache_valid=false
    if [ -f "$cache_file" ]; then
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null)
        current_time=$(date +%s)
        if [ $((current_time - cache_time)) -lt 300 ]; then
            cache_valid=true
        fi
    fi

    if [ "$cache_valid" = true ]; then
        echo "Using cached system scan results" >> "$LOGS_PATH/Rom Inspector.txt"
        while IFS=':' read -r sys_name count; do
            if [ "$count" -gt 0 ]; then
                echo "$sys_name ($count ZIP files)" >> "$systems_menu"
                echo "$sys_name:$count" >> "$zip_counts_file"
                zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
                zip_count=$((zip_count + count))
                echo "System: $sys_name ($count ZIP files)" >> "$ZIP_ROMS_FILE"
                if [ -f "$roms_cache_dir/$sys_name.txt" ]; then
                    while IFS= read -r rom_name; do
                        echo "  Found: $rom_name" >> "$ZIP_ROMS_FILE"
                    done < "$roms_cache_dir/$sys_name.txt"
                fi
            fi
        done < "$cache_file"
    else
        echo "Scanning systems for ZIP ROMs..." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Scanning for ZIP ROMs..." 2 &
        MESSAGE_PID=$!
        : > "$cache_file" 2>/dev/null
        for dir in /mnt/SDCARD/Roms/*; do
            if [ -d "$dir" ]; then
                sys_name=$(basename "$dir")
                find "$dir" -type f -iname "*.zip" -maxdepth 1 | sort > "$roms_cache_dir/$sys_name.txt"
                count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                if [ "$count" -gt 0 ]; then
                    echo "$sys_name ($count ZIP files)" >> "$systems_menu"
                    echo "$sys_name:$count" >> "$zip_counts_file"
                    echo "$sys_name:$count" >> "$cache_file"
                    zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
                    zip_count=$((zip_count + count))
                    echo "System: $sys_name ($count ZIP files)" >> "$ZIP_ROMS_FILE"
                    while IFS= read -r file; do
                        rom_name=$(basename "$file")
                        echo "  Found: $rom_name" >> "$ZIP_ROMS_FILE"
                    done < "$roms_cache_dir/$sys_name.txt"
                fi
            fi
        done
        kill $MESSAGE_PID 2>/dev/null
    fi

    # Add global action options
    printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"

    # Format zip_summary
    if [ -n "$zip_summary" ]; then
        zip_summary=$(echo "$zip_summary" | sed 's/;$//' | sed 's/;/ - /g')
        echo "ZIP ROMs Summary: $zip_summary" >> "$LOGS_PATH/Rom Inspector.txt"
        echo "ZIP ROMs Summary: $zip_summary" >> "$ZIP_ROMS_FILE"
    fi

    if [ ! -s "$systems_menu" ]; then
        echo "No systems with ZIP ROMs found" >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No systems with ZIP ROMs found" >> "$ZIP_ROMS_FILE"
        show_message "No ZIP ROMs found in any system." 2
        sleep 1
        rm -rf "$systems_menu" "$zip_action_menu" "$keep_zip_menu" "$zip_counts_file" "$roms_cache_dir" "$cache_file" 2>/dev/null
        show_message "Results in /mnt/SDCARD/zip_roms_report.txt" 2
        sleep 1
        return 0
    fi

    # Systems menu loop
    while true; do
        rm -f /tmp/minui-output 2>/dev/null
        minui-list --disable-auto-sleep \
            --item-key systems_zip \
            --file "$systems_menu" \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with ZIP ROMs" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?
        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User exited systems menu (exit code: $MINUI_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection in systems menu: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Invalid selection in systems menu." 2
            sleep 1
            break
        fi

        selected_option=$(sed -n "$((idx + 1))p" "$systems_menu" 2>/dev/null)
        if [ -z "$selected_option" ]; then
            echo "Error: Failed to retrieve selected option for index $idx" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Failed to retrieve selected option." 2
            sleep 1
            break
        fi
        echo "Selected option: $selected_option" >> "$LOGS_PATH/Rom Inspector.txt"

        # Handle global actions
        case "$selected_option" in
            "Decompress all ZIP ROMs")
                echo "Processing Decompress all ZIP ROMs..." >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Decompressing ZIP ROMs..." &
                MESSAGE_PID=$!
                for dir in /mnt/SDCARD/Roms/*; do
                    if [ -d "$dir" ]; then
                        sys_name=$(basename "$dir")
                        if [ -f "$roms_cache_dir/$sys_name.txt" ]; then
                            while IFS= read -r file; do
                                if [ -f "$file" ]; then
                                    rom_name=$(basename "$file")
                                    if unzip -t "$file" >/dev/null 2>&1; then
                                        if unzip -o "$file" -d "$dir" >> "$LOGS_PATH/Rom Inspector.txt" 2>&1; then
                                            echo "Successfully decompressed $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                            echo "  Action: Decompressed $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                            decompressed_count=$((decompressed_count + 1))
                                        else
                                            echo "Error: Failed to decompress $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                            echo "  Action: Failed to decompress $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                            skipped_count=$((skipped_count + 1))
                                        fi
                                    else
                                        echo "Error: Invalid or corrupted ZIP file: $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                        echo "  Action: Skipped $rom_name in $sys_name (invalid ZIP)" >> "$ZIP_ROMS_FILE"
                                        skipped_count=$((skipped_count + 1))
                                    fi
                                else
                                    echo "Error: File $file does not exist in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                    echo "  Action: Skipped $file in $sys_name (file does not exist)" >> "$ZIP_ROMS_FILE"
                                    skipped_count=$((skipped_count + 1))
                                fi
                            done < "$roms_cache_dir/$sys_name.txt"
                        fi
                    fi
                done
                kill $MESSAGE_PID 2>/dev/null
                show_message "All ZIP ROMs decompressed!" 2
                echo "All ZIP ROMs decompressed!" >> "$LOGS_PATH/Rom Inspector.txt"
                echo "  Action: All ZIP ROMs decompressed" >> "$ZIP_ROMS_FILE"
                rm -rf "$cache_file" "$roms_cache_dir" 2>/dev/null
                # Update system menu and caches
                : > "$systems_menu" 2>/dev/null
                : > "$zip_counts_file" 2>/dev/null
                zip_count=0
                zip_summary=""
                for dir in /mnt/SDCARD/Roms/*; do
                    if [ -d "$dir" ]; then
                        sys_name=$(basename "$dir")
                        find "$dir" -type f -iname "*.zip" -maxdepth 1 | sort > "$roms_cache_dir/$sys_name.txt"
                        count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                        if [ "$count" -gt 0 ]; then
                            echo "$sys_name ($count ZIP files)" >> "$systems_menu"
                            echo "$sys_name:$count" >> "$zip_counts_file"
                            echo "$sys_name:$count" >> "$cache_file"
                            zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
                            zip_count=$((zip_count + count))
                            while IFS= read -r file; do
                                rom_name=$(basename "$file")
                                echo "  Found: $rom_name" >> "$ZIP_ROMS_FILE"
                            done < "$roms_cache_dir/$sys_name.txt"
                        fi
                    fi
                done
                printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"
                continue
                ;;
            "Delete all ZIP ROMs")
                echo "Processing Delete all ZIP ROMs..." >> "$LOGS_PATH/Rom Inspector.txt"
                if confirm_deletion "all ZIP ROMs" "all ZIP ROMs"; then
                    show_message "Deleting ZIP ROMs..." &
                    MESSAGE_PID=$!
                    for dir in /mnt/SDCARD/Roms/*; do
                        if [ -d "$dir" ]; then
                            sys_name=$(basename "$dir")
                            if [ -f "$roms_cache_dir/$sys_name.txt" ]; then
                                while IFS= read -r file; do
                                    if [ -f "$file" ]; then
                                        rom_name=$(basename "$file")
                                        if rm -f "$file"; then
                                            echo "Deleted ZIP ROM: $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                            echo "  Action: Deleted $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                            deleted_count=$((deleted_count + 1))
                                        else
                                            echo "Error: Failed to delete $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                            echo "  Action: Failed to delete $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                            skipped_count=$((skipped_count + 1))
                                        fi
                                    else
                                        echo "Error: File $file does not exist in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                        echo "  Action: Skipped $file in $sys_name (file does not exist)" >> "$ZIP_ROMS_FILE"
                                        skipped_count=$((skipped_count + 1))
                                    fi
                                done < "$roms_cache_dir/$sys_name.txt"
                            fi
                        fi
                    done
                    kill $MESSAGE_PID 2>/dev/null
                    show_message "All ZIP ROMs deleted!" 2
                    echo "All ZIP ROMs deleted!" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "  Action: All ZIP ROMs deleted" >> "$ZIP_ROMS_FILE"
                    rm -rf "$cache_file" "$roms_cache_dir" 2>/dev/null
                    # Update system menu and caches
                    : > "$systems_menu" 2>/dev/null
                    : > "$zip_counts_file" 2>/dev/null
                    zip_count=0
                    zip_summary=""
                    for dir in /mnt/SDCARD/Roms/*; do
                        if [ -d "$dir" ]; then
                            sys_name=$(basename "$dir")
                            find "$dir" -type f -iname "*.zip" -maxdepth 1 | sort > "$roms_cache_dir/$sys_name.txt"
                            count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                            if [ "$count" -gt 0 ]; then
                                echo "$sys_name ($count ZIP files)" >> "$systems_menu"
                                echo "$sys_name:$count" >> "$zip_counts_file"
                                echo "$sys_name:$count" >> "$cache_file"
                                zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
                                zip_count=$((zip_count + count))
                                while IFS= read -r file; do
                                    rom_name=$(basename "$file")
                                    echo "  Found: $rom_name" >> "$ZIP_ROMS_FILE"
                                done < "$roms_cache_dir/$sys_name.txt"
                            fi
                        fi
                    done
                    printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"
                else
                    echo "User cancelled deletion of all ZIP ROMs" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "  Action: Skipped deletion of all ZIP ROMs" >> "$ZIP_ROMS_FILE"
                fi
                continue
                ;;
            "Decompress and delete all ZIP ROMs")
                echo "Processing Decompress and delete all ZIP ROMs..." >> "$LOGS_PATH/Rom Inspector.txt"
                if confirm_deletion "all ZIP ROMs" "all ZIP ROMs"; then
                    show_message "Decompressing and deleting ZIP ROMs..." &
                    MESSAGE_PID=$!
                    for dir in /mnt/SDCARD/Roms/*; do
                        if [ -d "$dir" ]; then
                            sys_name=$(basename "$dir")
                            if [ -f "$roms_cache_dir/$sys_name.txt" ]; then
                                while IFS= read -r file; do
                                    if [ -f "$file" ]; then
                                        rom_name=$(basename "$file")
                                        if unzip -t "$file" >/dev/null 2>&1; then
                                            if unzip -o "$file" -d "$dir" >> "$LOGS_PATH/Rom Inspector.txt" 2>&1; then
                                                echo "Successfully decompressed $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                                echo "  Action: Decompressed $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                                decompressed_count=$((decompressed_count + 1))
                                                if rm -f "$file"; then
                                                    echo "Deleted original ZIP: $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                                    echo "  Action: Decompressed and deleted $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                                    deleted_count=$((deleted_count + 1))
                                                else
                                                    echo "Error: Failed to delete $rom_name in $sys_name after decompression" >> "$LOGS_PATH/Rom Inspector.txt"
                                                    echo "  Action: Decompressed but failed to delete $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                                    skipped_count=$((skipped_count + 1))
                                                fi
                                            else
                                                echo "Error: Failed to decompress $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                                echo "  Action: Failed to decompress $rom_name in $sys_name" >> "$ZIP_ROMS_FILE"
                                                skipped_count=$((skipped_count + 1))
                                            fi
                                        else
                                            echo "Error: Invalid or corrupted ZIP file: $rom_name in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                            echo "  Action: Skipped $rom_name in $sys_name (invalid ZIP)" >> "$ZIP_ROMS_FILE"
                                            skipped_count=$((skipped_count + 1))
                                        fi
                                    else
                                        echo "Error: File $file does not exist in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                        echo "  Action: Skipped $file in $sys_name (file does not exist)" >> "$ZIP_ROMS_FILE"
                                        skipped_count=$((skipped_count + 1))
                                    fi
                                done < "$roms_cache_dir/$sys_name.txt"
                            fi
                        fi
                    done
                    kill $MESSAGE_PID 2>/dev/null
                    show_message "All ZIP ROMs decompressed and deleted!" 2
                    echo "All ZIP ROMs decompressed and deleted!" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "  Action: All ZIP ROMs decompressed and deleted" >> "$ZIP_ROMS_FILE"
                    rm -rf "$cache_file" "$roms_cache_dir" 2>/dev/null
                    # Update system menu and caches
                    : > "$systems_menu" 2>/dev/null
                    : > "$zip_counts_file" 2>/dev/null
                    zip_count=0
                    zip_summary=""
                    for dir in /mnt/SDCARD/Roms/*; do
                        if [ -d "$dir" ]; then
                            sys_name=$(basename "$dir")
                            find "$dir" -type f -iname "*.zip" -maxdepth 1 | sort > "$roms_cache_dir/$sys_name.txt"
                            count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                            if [ "$count" -gt 0 ]; then
                                echo "$sys_name ($count ZIP files)" >> "$systems_menu"
                                echo "$sys_name:$count" >> "$zip_counts_file"
                                echo "$sys_name:$count" >> "$cache_file"
                                zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
                                zip_count=$((zip_count + count))
                                while IFS= read -r file; do
                                    rom_name=$(basename "$file")
                                    echo "  Found: $rom_name" >> "$ZIP_ROMS_FILE"
                                done < "$roms_cache_dir/$sys_name.txt"
                            fi
                        fi
                    done
                    printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"
                else
                    echo "User cancelled decompress and delete all ZIP ROMs" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "  Action: Skipped decompress and delete all ZIP ROMs" >> "$ZIP_ROMS_FILE"
                fi
                continue
                ;;
            *)
                sys_name=$(echo "$selected_option" | sed 's/ ([0-9]* ZIP files)//')
                if [ -z "$sys_name" ]; then
                    echo "Error: Failed to retrieve system name for index $idx" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to retrieve system name." 2
                    sleep 1
                    break
                fi
                echo "Selected system: $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                ;;
        esac

        # ROMs menu loop
        while true; do
            : > "$roms_menu" 2>/dev/null || {
                echo "Error: Failed to create $roms_menu" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to create ROMs menu." 2
                sleep 2
                break
            }

            # Use cached ROM list if available and valid
            if [ -f "$roms_cache_dir/$sys_name.txt" ] && [ -s "$roms_cache_dir/$sys_name.txt" ]; then
                while IFS= read -r file; do
                    rom_name=$(basename "$file")
                    echo "$rom_name" >> "$roms_menu"
                done < "$roms_cache_dir/$sys_name.txt"
            else
                find "/mnt/SDCARD/Roms/$sys_name" -type f -iname "*.zip" -maxdepth 1 | sort > "$roms_cache_dir/$sys_name.txt"
                while IFS= read -r file; do
                    rom_name=$(basename "$file")
                    echo "$rom_name" >> "$roms_menu"
                done < "$roms_cache_dir/$sys_name.txt"
            fi

            if [ ! -s "$roms_menu" ]; then
                echo "No ZIP ROMs found in $sys_name" >> "$LOGS_PATH/Rom Inspector.txt"
                echo "No ZIP ROMs found in $sys_name" >> "$ZIP_ROMS_FILE"
                show_message "No ZIP ROMs found in $sys_name." 2
                sleep 1
                rm -f "$roms_menu" 2>/dev/null
                break
            fi

            rm -f /tmp/minui-output 2>/dev/null
            minui-list --disable-auto-sleep \
                --item-key roms_zip \
                --file "$roms_menu" \
                --format text \
                --cancel-text "BACK" \
                --title "ZIP ROMs in $sys_name" \
                --write-location /tmp/minui-output \
                --write-value state
            ROMS_EXIT_CODE=$?
            if [ "$ROMS_EXIT_CODE" -ne 0 ]; then
                echo "User exited ROMs menu for $sys_name (exit code: $ROMS_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            rom_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$rom_idx" = "null" ] || [ -z "$rom_idx" ] || [ "$rom_idx" = "-1" ]; then
                echo "Invalid or no selection in ROMs menu for $sys_name: idx=$rom_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Invalid selection in ROMs menu." 2
                sleep 1
                break
            fi

            rom_name=$(sed -n "$((rom_idx + 1))p" "$roms_menu" 2>/dev/null)
            if [ -z "$rom_name" ]; then
                echo "Error: Failed to retrieve ROM name for index $rom_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to retrieve ROM name." 2
                sleep 1
                break
            fi
            file="/mnt/SDCARD/Roms/$sys_name/$rom_name"
            echo "Selected ZIP ROM: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"

            rm -f /tmp/minui-output 2>/dev/null
            minui-list --disable-auto-sleep \
                --item-key zip_action \
                --file "$zip_action_menu" \
                --format text \
                --cancel-text "CANCEL" \
                --title "Action for ZIP ROM: $rom_name" \
                --write-location /tmp/minui-output \
                --write-value state
            ACTION_EXIT_CODE=$?
            if [ "$ACTION_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled action for $rom_name (exit code: $ACTION_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
                echo "  Action: Skipped $rom_name" >> "$ZIP_ROMS_FILE"
                skipped_count=$((skipped_count + 1))
                continue
            fi

            action_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$action_idx" = "null" ] || [ -z "$action_idx" ] || [ "$action_idx" = "-1" ]; then
                echo "Invalid or no selection in action menu for $rom_name: idx=$action_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Invalid action selection for $rom_name." 2
                sleep 1
                echo "  Action: Skipped $rom_name (error: invalid action selection)" >> "$ZIP_ROMS_FILE"
                skipped_count=$((skipped_count + 1))
                continue
            fi
            action=$(sed -n "$((action_idx + 1))p" "$zip_action_menu" 2>/dev/null)
            if [ -z "$action" ]; then
                echo "Error: Failed to retrieve action for index $action_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to retrieve action for $rom_name." 2
                sleep 1
                echo "  Action: Skipped $rom_name (error: failed to retrieve action)" >> "$ZIP_ROMS_FILE"
                skipped_count=$((skipped_count + 1))
                continue
            fi
            echo "Selected action for $rom_name: $action" >> "$LOGS_PATH/Rom Inspector.txt"

            case "$action" in
                "Decompress ZIP")
                    if [ ! -f "$file" ]; then
                        echo "Error: File $file does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: File $rom_name does not exist." 2
                        sleep 1
                        echo "  Action: Skipped $rom_name (file does not exist)" >> "$ZIP_ROMS_FILE"
                        skipped_count=$((skipped_count + 1))
                        continue
                    fi
                    show_message "Decompressing $rom_name..." &
                    MESSAGE_PID=$!
                    if unzip -t "$file" >/dev/null 2>&1; then
                        if unzip -o "$file" -d "/mnt/SDCARD/Roms/$sys_name" >> "$LOGS_PATH/Rom Inspector.txt" 2>&1; then
                            kill $MESSAGE_PID 2>/dev/null
                            echo "Successfully decompressed $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                            echo "  Action: Decompressed $rom_name" >> "$ZIP_ROMS_FILE"
                            decompressed_count=$((decompressed_count + 1))
                            rm -f /tmp/minui-output 2>/dev/null
                            minui-list --disable-auto-sleep \
                                --item-key keep_zip \
                                --file "$keep_zip_menu" \
                                --format text \
                                --cancel-text "CANCEL" \
                                --title "Keep or delete original ZIP: $rom_name" \
                                --write-location /tmp/minui-output \
                                --write-value state
                            KEEP_EXIT_CODE=$?
                            if [ "$KEEP_EXIT_CODE" -ne 0 ]; then
                                echo "User cancelled keep/delete action for $rom_name (exit code: $KEEP_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
                                echo "  Action: Kept original ZIP for $rom_name (cancelled)" >> "$ZIP_ROMS_FILE"
                                continue
                            fi
                            keep_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
                            if [ "$keep_idx" = "null" ] || [ -z "$keep_idx" ] || [ "$keep_idx" = "-1" ]; then
                                echo "Invalid or no selection in keep/delete menu for $rom_name: idx=$keep_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "Error: Invalid keep/delete selection for $rom_name." 2
                                sleep 1
                                echo "  Action: Kept original ZIP for $rom_name (error: invalid selection)" >> "$ZIP_ROMS_FILE"
                                continue
                            fi
                            keep_action=$(sed -n "$((keep_idx + 1))p" "$keep_zip_menu" 2>/dev/null)
                            if [ -z "$keep_action" ]; then
                                echo "Error: Failed to retrieve keep/delete action for index $keep_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "Error: Failed to retrieve keep/delete action for $rom_name." 2
                                sleep 1
                                echo "  Action: Kept original ZIP for $rom_name (error: failed to retrieve action)" >> "$ZIP_ROMS_FILE"
                                continue
                            fi
                            echo "Selected keep/delete action for $rom_name: $keep_action" >> "$LOGS_PATH/Rom Inspector.txt"
                            if [ "$keep_action" = "Delete" ]; then
                                if confirm_deletion "$file" "ZIP ROM"; then
                                    show_message "Deleting $rom_name..." &
                                    MESSAGE_PID=$!
                                    if rm -f "$file"; then
                                        kill $MESSAGE_PID 2>/dev/null
                                        echo "Deleted original ZIP: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                        echo "  Action: Decompressed and deleted original ZIP for $rom_name" >> "$ZIP_ROMS_FILE"
                                        deleted_count=$((deleted_count + 1))
                                        # Update ROM cache
                                        grep -v "^$file$" "$roms_cache_dir/$sys_name.txt" > "$roms_cache_dir/$sys_name.tmp" && mv "$roms_cache_dir/$sys_name.tmp" "$roms_cache_dir/$sys_name.txt"
                                        # Update system cache
                                        count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                                        tmp_cache="/tmp/cache_tmp.txt"
                                        : > "$tmp_cache"
                                        while IFS=':' read -r name cnt; do
                                            if [ "$name" = "$sys_name" ]; then
                                                [ "$count" -gt 0 ] && echo "$name:$count" >> "$tmp_cache"
                                            else
                                                echo "$name:$cnt" >> "$tmp_cache"
                                            fi
                                        done < "$cache_file"
                                        mv "$tmp_cache" "$cache_file" 2>/dev/null
                                        # Update counts file
                                        : > "$tmp_cache"
                                        while IFS=':' read -r name cnt; do
                                            if [ "$name" = "$sys_name" ]; then
                                                [ "$count" -gt 0 ] && echo "$name:$count" >> "$tmp_cache"
                                            else
                                                echo "$name:$cnt" >> "$tmp_cache"
                                            fi
                                        done < "$zip_counts_file"
                                        mv "$tmp_cache" "$zip_counts_file" 2>/dev/null
                                        # Update systems menu
                                        : > "$systems_menu"
                                        while IFS=':' read -r name cnt; do
                                            [ "$cnt" -gt 0 ] && echo "$name ($cnt ZIP files)" >> "$systems_menu"
                                        done < "$zip_counts_file"
                                        printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"
                                    else
                                        kill $MESSAGE_PID 2>/dev/null
                                        echo "Error: Failed to delete $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                        show_message "Error: Failed to delete $rom_name." 2
                                        sleep 1
                                        echo "  Action: Decompressed but failed to delete original ZIP for $rom_name" >> "$ZIP_ROMS_FILE"
                                    fi
                                else
                                    echo "User chose to keep original ZIP: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                    echo "  Action: Decompressed and kept original ZIP for $rom_name" >> "$ZIP_ROMS_FILE"
                                fi
                            else
                                echo "User chose to keep original ZIP: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                                echo "  Action: Decompressed and kept original ZIP for $rom_name" >> "$ZIP_ROMS_FILE"
                            fi
                        else
                            kill $MESSAGE_PID 2>/dev/null
                            echo "Error: Failed to decompress $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                            show_message "Error: Failed to decompress $rom_name." 2
                            sleep 1
                            echo "  Action: Failed to decompress $rom_name" >> "$ZIP_ROMS_FILE"
                            skipped_count=$((skipped_count + 1))
                        fi
                    else
                        kill $MESSAGE_PID 2>/dev/null
                        echo "Error: Invalid or corrupted ZIP file: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: Invalid ZIP $rom_name." 2
                        sleep 1
                        echo "  Action: Skipped $rom_name (invalid ZIP)" >> "$ZIP_ROMS_FILE"
                        skipped_count=$((skipped_count + 1))
                    fi
                    ;;
                "Delete ZIP")
                    if [ ! -f "$file" ]; then
                        echo "Error: File $file does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: File $rom_name does not exist." 2
                        sleep 1
                        echo "  Action: Skipped $rom_name (file does not exist)" >> "$ZIP_ROMS_FILE"
                        skipped_count=$((skipped_count + 1))
                        continue
                    fi
                    if confirm_deletion "$file" "ZIP ROM"; then
                        show_message "Deleting $rom_name..." &
                        MESSAGE_PID=$!
                        if rm -f "$file"; then
                            kill $MESSAGE_PID 2>/dev/null
                            echo "Deleted ZIP ROM: $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                            echo "  Action: Deleted $rom_name" >> "$ZIP_ROMS_FILE"
                            deleted_count=$((deleted_count + 1))
                            # Update ROM cache
                            grep -v "^$file$" "$roms_cache_dir/$sys_name.txt" > "$roms_cache_dir/$sys_name.tmp" && mv "$roms_cache_dir/$sys_name.tmp" "$roms_cache_dir/$sys_name.txt"
                            # Update system cache
                            count=$(wc -l < "$roms_cache_dir/$sys_name.txt")
                            tmp_cache="/tmp/cache_tmp.txt"
                            : > "$tmp_cache"
                            while IFS=':' read -r name cnt; do
                                if [ "$name" = "$sys_name" ]; then
                                    [ "$count" -gt 0 ] && echo "$name:$count" >> "$tmp_cache"
                                else
                                    echo "$name:$cnt" >> "$tmp_cache"
                                fi
                            done < "$cache_file"
                            mv "$tmp_cache" "$cache_file" 2>/dev/null
                            # Update counts file
                            : > "$tmp_cache"
                            while IFS=':' read -r name cnt; do
                                if [ "$name" = "$sys_name" ]; then
                                    [ "$count" -gt 0 ] && echo "$name:$count" >> "$tmp_cache"
                                else
                                    echo "$name:$cnt" >> "$tmp_cache"
                                fi
                            done < "$zip_counts_file"
                            mv "$tmp_cache" "$zip_counts_file" 2>/dev/null
                            # Update systems menu
                            : > "$systems_menu"
                            while IFS=':' read -r name cnt; do
                                [ "$cnt" -gt 0 ] && echo "$name ($cnt ZIP files)" >> "$systems_menu"
                            done < "$zip_counts_file"
                            printf "Decompress all ZIP ROMs\nDelete all ZIP ROMs\nDecompress and delete all ZIP ROMs\n" >> "$systems_menu"
                        else
                            kill $MESSAGE_PID 2>/dev/null
                            echo "Error: Failed to delete $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                            show_message "Error: Failed to delete $rom_name." 2
                            sleep 1
                            echo "  Action: Failed to delete $rom_name" >> "$ZIP_ROMS_FILE"
                        fi
                    else
                        echo "User cancelled deletion of $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                        echo "  Action: Skipped $rom_name (cancelled deletion)" >> "$ZIP_ROMS_FILE"
                        skipped_count=$((skipped_count + 1))
                    fi
                    ;;
                "Skip ZIP")
                    echo "Skipped $rom_name" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "  Action: Skipped $rom_name" >> "$ZIP_ROMS_FILE"
                    skipped_count=$((skipped_count + 1))
                    ;;
                *)
                    echo "Error: Invalid action for $rom_name: $action" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Invalid action for $rom_name." 2
                    sleep 1
                    echo "  Action: Skipped $rom_name (invalid action)" >> "$ZIP_ROMS_FILE"
                    skipped_count=$((skipped_count + 1))
                    ;;
            esac
        done
        rm -f "$roms_menu" 2>/dev/null
    done

    # Final summary
    zip_summary=""
    if [ -s "$zip_counts_file" ]; then
        while IFS=':' read -r sys_name count; do
            if [ "$count" -gt 0 ]; then
                zip_summary="$zip_summary$sys_name: $count ZIP file(s);"
            fi
        done < "$zip_counts_file"
        zip_summary=$(echo "$zip_summary" | sed 's/;$//' | sed 's/;/ - /g')
    fi

    echo "ZIP ROM check completed. Found: $zip_count, Decompressed: $decompressed_count, Deleted: $deleted_count, Skipped: $skipped_count" >> "$LOGS_PATH/Rom Inspector.txt"
    if [ -n "$zip_summary" ]; then
        echo "Final ZIP ROMs Summary: $zip_summary" >> "$LOGS_PATH/Rom Inspector.txt"
        echo "Final ZIP ROMs Summary: $zip_summary" >> "$ZIP_ROMS_FILE"
    fi
    echo "Summary: Found: $zip_count, Decompressed: $decompressed_count, Deleted: $deleted_count, Skipped: $skipped_count" >> "$ZIP_ROMS_FILE"
    show_message "Results saved in /mnt/SDCARD/zip_roms_report.txt" 3
    sleep 0
    rm -rf "$systems_menu" "$zip_action_menu" "$keep_zip_menu" "$zip_counts_file" "$roms_cache_dir" "$cache_file" 2>/dev/null
}

check_roms_sizes() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="$ROM_SIZES_FILE"
    MAX_FILES=1000  # Limite du nombre de fichiers à traiter pour éviter la surcharge

    show_message "Scanning ROM sizes..." forever
    LOADING_PID=$!

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== ROM Sizes Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create rom_sizes_report.txt." 5
        return 1
    }

    # Initialize variables
    VALID_SYSTEMS_FOUND=0
    PROBLEMATIC_ROM_COUNT=0

    # Create menu file
    > /tmp/rom_sizes.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/rom_sizes.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create menu file." 5
        return 1
    }

    # Process each system
    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || continue
        SYS_NAME="${SYS_PATH##*/}"
        
        # Skip system directories
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        # Skip PS1 if too many ROMs
        if { [ "$SYS_NAME" = "Sony PlayStation (PS)" ] || [ "$SYS_NAME" = "PS" ]; } && \
           [ $(find "$SYS_PATH" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.iso' -o -name '*.img' -o -name '*.zip' \) | wc -l) -gt 50 ]; then
            echo "$SYS_NAME - Too many ROMs (check report)" >> /tmp/rom_sizes.menu
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Too many ROMs - skipping detailed scan" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            continue
        fi

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && continue

        THRESHOLDS=$(get_size_thresholds "$SYS_NAME")
        MIN_SIZE=$(echo "$THRESHOLDS" | awk '{print $1}')
        MAX_SIZE=$(echo "$THRESHOLDS" | awk '{print $2}')

        # Create temp file
        TEMP_FILE=$(mktemp)
        PROBLEM_COUNT=0

        # Find and process ROMs with limit
        FILE_COUNT=0
        find "$SYS_PATH" -maxdepth 1 -type f | while read -r ROM; do
            FILE_COUNT=$((FILE_COUNT + 1))
            if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*|*.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                SIZE=$(stat -c%s "$ROM" 2>/dev/null || echo 0)
                if [ "$SIZE" -eq 0 ]; then
                    echo "Warning: Failed to get size for $ROM" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                fi
                if [ "$SIZE" -lt "$MIN_SIZE" ] || [ "$SIZE" -gt "$MAX_SIZE" ]; then
                    PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
                    SIZE_KB=$((SIZE / 1024))
                    if [ "$SIZE" -lt "$MIN_SIZE" ]; then
                        echo "$ROM_BASENAME - ${SIZE_KB}KB (too small)" >> "$TEMP_FILE"
                    else
                        SIZE_MB=$((SIZE / 1048576))
                        echo "$ROM_BASENAME - ${SIZE_MB}MB (too large)" >> "$TEMP_FILE"
                    fi
                fi
            fi
        done

        if [ "$PROBLEM_COUNT" -gt 0 ]; then
            echo "$SYS_NAME - $PROBLEM_COUNT problematic ROM(s)" >> /tmp/rom_sizes.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            PROBLEMATIC_ROM_COUNT=$((PROBLEMATIC_ROM_COUNT + PROBLEM_COUNT))
            
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Problematic ROMs: $PROBLEM_COUNT" >> "$OUTPUT_FILE"
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
        
        rm -f "$TEMP_FILE"
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No ROMs with problematic sizes found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No problematic ROM sizes found." >> "$OUTPUT_FILE"
        show_message "No problematic ROM sizes found." 5
        return 0
    fi

    # Display systems menu
    while true; do
        minui-list --disable-auto-sleep \
            --item-key rom_sizes \
            --file /tmp/rom_sizes.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Problematic ROM Sizes" \
            --write-location /tmp/minui-output \
            --write-value state
            
        [ $? -ne 0 ] && break

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        [ -z "$idx" ] || [ "$idx" = "null" ] || [ "$idx" = "-1" ] && break

        selected_line=$(sed -n "$((idx + 1))p" /tmp/rom_sizes.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        # Skip if too many ROMs
        if echo "$selected_line" | grep -q "Too many ROMs"; then
            show_message "Too many ROMs - check report file" 3
            continue
        fi

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        VALID_EXTENSIONS=$(get_valid_extensions "$selected_sys")
        THRESHOLDS=$(get_size_thresholds "$selected_sys")
        MIN_SIZE=$(echo "$THRESHOLDS" | awk '{print $1}')
        MAX_SIZE=$(echo "$THRESHOLDS" | awk '{print $2}')

        show_message "Loading problematic ROMs for $selected_sys..." forever
        LOADING_PID=$!
        
        # Create temp file
        TEMP_FILE=$(mktemp)
        
        # Find and process ROMs with limit
        FILE_COUNT=0
        find "$SYS_PATH" -maxdepth 1 -type f | while read -r ROM; do
            FILE_COUNT=$((FILE_COUNT + 1))
            if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                echo "Warning: Too many files in $selected_sys, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*|*.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                SIZE=$(stat -c%s "$ROM" 2>/dev/null || echo 0)
                if [ "$SIZE" -eq 0 ]; then
                    echo "Warning: Failed to get size for $ROM" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                fi
                if [ "$SIZE" -lt "$MIN_SIZE" ] || [ "$SIZE" -gt "$MAX_SIZE" ]; then
                    SIZE_KB=$((SIZE / 1024))
                    if [ "$SIZE" -lt "$MIN_SIZE" ]; then
                        echo "$ROM_BASENAME - ${SIZE_KB}KB (too small)" >> "$TEMP_FILE"
                    else
                        SIZE_MB=$((SIZE / 1048576))
                        echo "$ROM_BASENAME - ${SIZE_MB}MB (too large)" >> "$TEMP_FILE"
                    fi
                fi
            fi
        done

        stop_loading

        if [ ! -s "$TEMP_FILE" ]; then
            rm -f "$TEMP_FILE"
            show_message "No problematic ROMs found for $selected_sys." 3
            continue
        fi

        # Display ROMs menu
        while true; do
            minui-list --disable-auto-sleep \
                --item-key rom_size_items \
                --file "$TEMP_FILE" \
                --format text \
                --cancel-text "BACK" \
                --title "Problematic ROMs for $selected_sys" \
                --write-location /tmp/minui-output \
                --write-value state
                
            [ $? -ne 0 ] && break

            rom_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            [ -z "$rom_idx" ] || [ "$rom_idx" = "null" ] || [ "$rom_idx" = "-1" ] && break

            selected_line=$(sed -n "$((rom_idx + 1))p" "$TEMP_FILE" 2>/dev/null)
            selected_rom=$(echo "$selected_line" | cut -d' ' -f1)

            ROM_TO_DELETE="$SYS_PATH/$selected_rom"
            if confirm_deletion "$ROM_TO_DELETE" "ROM"; then
                if rm -f "$ROM_TO_DELETE" 2>/dev/null; then
                    echo "Deleted ROM: $ROM_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "System: $selected_sys" >> "$OUTPUT_FILE"
                    echo "- Deleted: $selected_line" >> "$OUTPUT_FILE"
                    show_message "Deleted: $selected_rom" 3
                    # Refresh the list
                    grep -v "^$selected_rom " "$TEMP_FILE" > "${TEMP_FILE}.tmp" && mv "${TEMP_FILE}.tmp" "$TEMP_FILE"
                else
                    echo "Error: Failed to delete $ROM_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to delete $selected_rom." 5
                fi
            else
                show_message "Deletion cancelled for $selected_rom" 3
            fi
        done
        
        rm -f "$TEMP_FILE"
    done

    show_message "ROM sizes report saved to $OUTPUT_FILE" 5
    return 0
}

remove_duplicate_roms() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="/mnt/SDCARD/duplicate_roms_removed.txt"

    show_message "Scanning for duplicate ROMs..." forever
    LOADING_PID=$!
	sleep 0.5  # Ensure message is fully displayed before heavy operations

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== Duplicate ROMs Removal Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create duplicate_roms_removed.txt." 5
        return 1
    }

    # Determine if NextUI is used
    is_nextui=false
    image_folder=".media"
    if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
        is_nextui=true
    else
        image_folder=".res"
    fi
    echo "Using image folder for duplicate ROMs: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

    VALID_SYSTEMS_FOUND=0
    TOTAL_DUPLICATES_FOUND=0
    TOTAL_DUPLICATES_REMOVED=0

    > /tmp/duplicates.menu
    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || continue
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && continue

        > /tmp/rom_names.txt
        > /tmp/rom_names_only.txt
        DUPLICATE_COUNT=0
        for ROM in "$SYS_PATH"/*; do
            [ -f "$ROM" ] && [ -r "$ROM" ] || continue
            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*) continue ;;
                *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                ROM_NAME="${ROM_BASENAME%.*}"
                if grep -Fx "$ROM_NAME" /tmp/rom_names_only.txt >/dev/null; then
                    DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
                else
                    echo "$ROM_NAME" >> /tmp/rom_names_only.txt
                fi
                echo "$ROM_NAME|$ROM" >> /tmp/rom_names.txt
            fi
        done

        > /tmp/rom_names_duplicates.txt
        sort /tmp/rom_names.txt | cut -d'|' -f1 | uniq -d > /tmp/rom_names_duplicates.txt
        if [ -s /tmp/rom_names_duplicates.txt ]; then
            if [ "$DUPLICATE_COUNT" -eq 1 ]; then
                echo "$SYS_NAME - 1 duplicate" >> /tmp/duplicates.menu
            else
                echo "$SYS_NAME - $DUPLICATE_COUNT duplicates" >> /tmp/duplicates.menu
            fi
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_DUPLICATES_FOUND=$((TOTAL_DUPLICATES_FOUND + DUPLICATE_COUNT))
        fi
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with duplicate ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No duplicate ROMs found." >> "$OUTPUT_FILE"
        show_message "No duplicate ROMs found." 5
        return 0
    fi

    while true; do
        minui-list --disable-auto-sleep \
            --item-key duplicates \
            --file /tmp/duplicates.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Duplicate ROMs" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ ! -f /tmp/minui-output ] || [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            break
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/duplicates.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        VALID_EXTENSIONS=$(get_valid_extensions "$selected_sys")
        show_message "Loading duplicates for $selected_sys..." forever
        LOADING_PID=$!
        > /tmp/roms_duplicates.menu
        > /tmp/rom_names.txt
        > /tmp/rom_names_only.txt
        for ROM in "$SYS_PATH"/*; do
            [ -f "$ROM" ] && [ -r "$ROM" ] || continue
            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*) continue ;;
                *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                ROM_NAME="${ROM_BASENAME%.*}"
                echo "$ROM_NAME|$ROM" >> /tmp/rom_names.txt
            fi
        done

        sort /tmp/rom_names.txt | cut -d'|' -f1 | uniq -d > /tmp/roms_duplicates.menu
        stop_loading

        if [ ! -s /tmp/roms_duplicates.menu ]; then
            show_message "No duplicates found for $selected_sys." 5
            continue
        fi

        while true; do
            minui-list --disable-auto-sleep \
                --item-key rom_duplicates \
                --file /tmp/roms_duplicates.menu \
                --format text \
                --cancel-text "BACK" \
                --title "Duplicates for $selected_sys" \
                --write-location /tmp/minui-output \
                --write-value state
            MINUI_EXIT_CODE=$?

            if [ ! -f /tmp/minui-output ] || [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                break
            fi

            rom_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$rom_idx" = "null" ] || [ -z "$rom_idx" ] || [ "$rom_idx" = "-1" ]; then
                break
            fi

            selected_rom_name=$(sed -n "$((rom_idx + 1))p" /tmp/roms_duplicates.menu 2>/dev/null)

            > /tmp/rom_files.menu
            for ROM in "$SYS_PATH/$selected_rom_name".*; do
                [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                ROM_BASENAME="${ROM##*/}"
                if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                    echo "$ROM_BASENAME" >> /tmp/rom_files.menu
                fi
            done

            if [ ! -s /tmp/rom_files.menu ]; then
                show_message "Error: No files found for $selected_rom_name." 5
                continue
            fi

            while true; do
                minui-list --disable-auto-sleep \
                    --item-key rom_file \
                    --file /tmp/rom_files.menu \
                    --format text \
                    --cancel-text "KEEP ALL" \
                    --title "Delete a file for $selected_rom_name" \
                    --write-location /tmp/minui-output \
                    --write-value state
                MINUI_EXIT_CODE=$?

                if [ ! -f /tmp/minui-output ] || [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                    break
                fi

                file_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
                if [ "$file_idx" = "null" ] || [ -z "$file_idx" ] || [ "$file_idx" = "-1" ]; then
                    break
                fi

                selected_file=$(sed -n "$((file_idx + 1))p" /tmp/rom_files.menu 2>/dev/null)

                ROM_TO_DELETE="$SYS_PATH/$selected_file"
                if confirm_deletion "$ROM_TO_DELETE" "ROM"; then
                    if rm -f "$ROM_TO_DELETE" 2>/dev/null; then
                        echo "Deleted ROM: $ROM_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                        echo "System: $selected_sys" >> "$OUTPUT_FILE"
                        echo "- Deleted: $selected_file" >> "$OUTPUT_FILE"
                        TOTAL_DUPLICATES_REMOVED=$((TOTAL_DUPLICATES_REMOVED + 1))
                        show_message "Deleted: $selected_file" 3

                        # Rebuild the list of duplicates for the current system
                        > /tmp/rom_names.txt
                        > /tmp/rom_names_only.txt
                        DUPLICATE_COUNT=0
                        for ROM in "$SYS_PATH"/*; do
                            [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                            ROM_BASENAME="${ROM##*/}"
                            case "$ROM_BASENAME" in
                                .*) continue ;;
                                *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
                            esac
                            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                                ROM_NAME="${ROM_BASENAME%.*}"
                                if grep -Fx "$ROM_NAME" /tmp/rom_names_only.txt >/dev/null; then
                                    DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
                                else
                                    echo "$ROM_NAME" >> /tmp/rom_names_only.txt
                                fi
                                echo "$ROM_NAME|$ROM" >> /tmp/rom_names.txt
                            fi
                        done

                        > /tmp/roms_duplicates.menu
                        sort /tmp/rom_names.txt | cut -d'|' -f1 | uniq -d > /tmp/roms_duplicates.menu

                        # Update duplicates.menu with new count or remove system if no duplicates remain
                        if [ "$DUPLICATE_COUNT" -gt 0 ]; then
                            if [ "$DUPLICATE_COUNT" -eq 1 ]; then
                                sed -i "/^$selected_sys - /c\\$selected_sys - 1 duplicate" /tmp/duplicates.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "Updated $selected_sys in duplicates.menu with 1 duplicate" >> "$LOGS_PATH/Rom Inspector.txt"
                            else
                                sed -i "/^$selected_sys - /c\\$selected_sys - $DUPLICATE_COUNT duplicates" /tmp/duplicates.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "Updated $selected_sys in duplicates.menu with $DUPLICATE_COUNT duplicates" >> "$LOGS_PATH/Rom Inspector.txt"
                            fi
                        else
                            sed -i "/^$selected_sys - /d" /tmp/duplicates.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                            echo "Removed $selected_sys from duplicates.menu as no duplicates remain" >> "$LOGS_PATH/Rom Inspector.txt"
                            break
                        fi
                    else
                        echo "Error: Failed to delete $ROM_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: Failed to delete $selected_file." 5
                    fi
                else
                    show_message "Deletion cancelled for $selected_file" 3
                fi
            done

            # Break the duplicates menu loop if no duplicates remain
            if [ ! -s /tmp/roms_duplicates.menu ]; then
                echo "No more duplicates for $selected_sys, exiting duplicates menu" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
        done

        # Break the systems menu loop if no systems with duplicates remain
        if [ ! -s /tmp/duplicates.menu ]; then
            echo "No systems with duplicate ROMs remain" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No systems with duplicate ROMs remain." 5
            break
        fi
    done

    echo "Total duplicates removed: $TOTAL_DUPLICATES_REMOVED" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total duplicates removed: $TOTAL_DUPLICATES_REMOVED" >> "$OUTPUT_FILE"
    show_message "Removed $TOTAL_DUPLICATES_REMOVED duplicate(s). Report: $OUTPUT_FILE" 5
    return 0
}

statistics() {
    ROMS_DIR="/mnt/SDCARD/Roms"

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    > /tmp/statistics.menu || {
        echo "Error: Failed to create /tmp/statistics.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create statistics menu." 5
        return 1
    }
    echo "View total ROMs per system" >> /tmp/statistics.menu
    echo "View percentage of ROMs with covers" >> /tmp/statistics.menu
    echo "Analyze disk usage" >> /tmp/statistics.menu
    echo "Generate Statistics Report" >> /tmp/statistics.menu

    while true; do
        minui-list --disable-auto-sleep \
            --item-key stats \
            --file /tmp/statistics.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Statistics" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ ! -f /tmp/minui-output ] || [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            break
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/statistics.menu 2>/dev/null)

        case "$selected_line" in
            "View total ROMs per system")
                show_message "Loading total ROMs per system..." forever
                LOADING_PID=$!

                > /tmp/total_roms.menu || {
                    stop_loading
                    echo "Error: Failed to create /tmp/total_roms.menu" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to create total ROMs menu." 5
                    return 1
                }

                TOTAL_ROM_COUNT=0
                VALID_SYSTEMS_FOUND=0

                for SYS_PATH in "$ROMS_DIR"/*; do
                    [ -d "$SYS_PATH" ] || continue
                    [ -r "$SYS_PATH" ] || continue
                    SYS_NAME="${SYS_PATH##*/}"
                    case "$SYS_NAME" in
                        .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
                    esac

                    VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
                    [ -z "$VALID_EXTENSIONS" ] && continue

                    ROM_COUNT=0
                    for ROM in "$SYS_PATH"/*; do
                        [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                        ROM_BASENAME="${ROM##*/}"
                        case "$ROM_BASENAME" in
                            .*) continue ;;
                            *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
                        esac
                        if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                            ROM_COUNT=$((ROM_COUNT + 1))
                        fi
                    done

                    [ "$ROM_COUNT" -eq 0 ] && continue

                    if [ "$ROM_COUNT" -eq 1 ]; then
                        echo "$SYS_NAME - $ROM_COUNT ROM" >> /tmp/total_roms.menu
                    else
                        echo "$SYS_NAME - $ROM_COUNT ROMs" >> /tmp/total_roms.menu
                    fi
                    TOTAL_ROM_COUNT=$((TOTAL_ROM_COUNT + ROM_COUNT))
                    VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
                done

                echo "Total ROMs: $TOTAL_ROM_COUNT" >> /tmp/total_roms.menu

                if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
                    stop_loading
                    echo "Error: No valid systems with ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: No valid systems found." 5
                    return 1
                fi

                stop_loading

                while true; do
                    minui-list --disable-auto-sleep \
                        --item-key total_roms \
                        --file /tmp/total_roms.menu \
                        --format text \
                        --cancel-text "BACK" \
                        --title "Total ROMs per System" \
                        --write-location /tmp/minui-output \
                        --write-value state
                    MINUI_EXIT_CODE=$?

                    if [ ! -f /tmp/minui-output ] || [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                        echo "User cancelled total ROMs menu (exit code: $MINUI_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
                        break
                    fi

                    idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
                    if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
                        echo "Invalid or no selection in total ROMs menu: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
                        break
                    fi

                    selected_system=$(sed -n "$((idx + 1))p" /tmp/total_roms.menu 2>/dev/null)
                    echo "Selected system: $selected_system" >> "$LOGS_PATH/Rom Inspector.txt"

                    # Check if the selection is the "Total ROMs" line
                    if echo "$selected_system" | grep -q "^Total ROMs:"; then
                        echo "User selected Total ROMs line, skipping ROM list display" >> "$LOGS_PATH/Rom Inspector.txt"
                        continue
                    fi

                    # Extract system name (remove ROM count part)
                    SYS_NAME=$(echo "$selected_system" | sed 's/ - [0-9]\+ ROMs\?$//')
                    SYS_PATH="$ROMS_DIR/$SYS_NAME"
                    echo "Processing ROM list for system: $SYS_NAME ($SYS_PATH)" >> "$LOGS_PATH/Rom Inspector.txt"

                    # Generate ROM list for the selected system
                    > /tmp/rom_list.menu || {
                        echo "Error: Failed to create /tmp/rom_list.menu" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: Failed to create ROM list menu." 5
                        break
                    }

                    VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
                    [ -z "$VALID_EXTENSIONS" ] && {
                        echo "Error: No valid extensions for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Error: No valid extensions for $SYS_NAME." 5
                        continue
                    }

                    ROM_COUNT=0
                    for ROM in "$SYS_PATH"/*; do
                        [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                        ROM_BASENAME="${ROM##*/}"
                        case "$ROM_BASENAME" in
                            .*) continue ;;
                            *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
                        esac
                        if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                            echo "$ROM_BASENAME" >> /tmp/rom_list.menu
                            ROM_COUNT=$((ROM_COUNT + 1))
                        fi
                    done

                    if [ "$ROM_COUNT" -eq 0 ]; then
                        echo "No ROMs found for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "No ROMs found for $SYS_NAME." 5
                        continue
                    fi

                    # Display ROM list
                    minui-list --disable-auto-sleep \
                        --item-key rom_list \
                        --file /tmp/rom_list.menu \
                        --format text \
                        --cancel-text "BACK" \
                        --title "ROMs for $SYS_NAME" \
                        --write-location /tmp/minui-output \
                        --write-value state
                    MINUI_ROM_EXIT_CODE=$?

                    if [ "$MINUI_ROM_EXIT_CODE" -ne 0 ]; then
                        echo "User cancelled ROM list for $SYS_NAME (exit code: $MINUI_ROM_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
                    fi
                done
                ;;
            "View percentage of ROMs with covers")
                show_message "Loading percentage of ROMs with covers..." forever
                LOADING_PID=$!

                > /tmp/covers_percentage.menu || {
                    stop_loading
                    echo "Error: Failed to create /tmp/covers_percentage.menu" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to create covers percentage menu." 5
                    return 1
                }

                TOTAL_ROM_COUNT=0
                TOTAL_COVER_COUNT=0
                VALID_SYSTEMS_FOUND=0

                for SYS_PATH in "$ROMS_DIR"/*; do
                    [ -d "$SYS_PATH" ] || continue
                    [ -r "$SYS_PATH" ] || continue
                    SYS_NAME="${SYS_PATH##*/}"
                    case "$SYS_NAME" in
                        .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
                    esac

                    VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
                    [ -z "$VALID_EXTENSIONS" ] && continue

                    ROM_COUNT=0
                    COVER_COUNT=0
                    for ROM in "$SYS_PATH"/*; do
                        [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                        ROM_BASENAME="${ROM##*/}"
                        case "$ROM_BASENAME" in
                            .*) continue ;;
                            *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
                        esac
                        if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                            ROM_COUNT=$((ROM_COUNT + 1))
                            COVER_FILE="$SYS_PATH/.media/${ROM_BASENAME%.*}.png"
                            if [ -f "$COVER_FILE" ]; then
                                COVER_COUNT=$((COVER_COUNT + 1))
                            fi
                        fi
                    done

                    [ "$ROM_COUNT" -eq 0 ] && continue

                    if [ "$ROM_COUNT" -gt 0 ]; then
                        PERCENTAGE=$(( (COVER_COUNT * 100) / ROM_COUNT ))
                    else
                        PERCENTAGE=0
                    fi

                    echo "$SYS_NAME - $PERCENTAGE% covers" >> /tmp/covers_percentage.menu
                    TOTAL_ROM_COUNT=$((TOTAL_ROM_COUNT + ROM_COUNT))
                    TOTAL_COVER_COUNT=$((TOTAL_COVER_COUNT + COVER_COUNT))
                    VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
                done

                if [ "$TOTAL_ROM_COUNT" -gt 0 ]; then
                    TOTAL_PERCENTAGE=$(( (TOTAL_COVER_COUNT * 100) / TOTAL_ROM_COUNT ))
                else
                    TOTAL_PERCENTAGE=0
                fi
                echo "Total: $TOTAL_PERCENTAGE% covers" >> /tmp/covers_percentage.menu

                if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
                    stop_loading
                    echo "Error: No valid systems with ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: No valid systems found." 5
                    return 1
                fi

                stop_loading

                minui-list --disable-auto-sleep \
                    --item-key covers_percentage \
                    --file /tmp/covers_percentage.menu \
                    --format text \
                    --cancel-text "BACK" \
                    --title "Percentage of ROMs with Covers" \
                    --write-location /tmp/minui-output \
                    --write-value state
                ;;
            "Analyze disk usage")
                analyze_disk_usage
                ;;
            "Generate Statistics Report")
                show_message "Generating statistics report..." forever
                LOADING_PID=$!

                if [ ! -w "/mnt/SDCARD" ]; then
                    echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Cannot write to /mnt/SDCARD." 5
                    stop_loading
                    return 1
                fi

                echo "=== Statistics Report ===" > "$STATS_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
                    echo "Error: Failed to initialize $STATS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to create statistics_report.txt." 5
                    stop_loading
                    return 1
                }

                TOTAL_ROM_COUNT=0
                TOTAL_COVER_COUNT=0
                TOTAL_SIZE=0
                VALID_SYSTEMS_FOUND=0
                MAX_FILES=1000  # Limite pour éviter la surcharge

                # Déterminer si NextUI est utilisé
                is_nextui=false
                image_folder=".media"
                if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
                    is_nextui=true
                else
                    image_folder=".res"
                fi
                echo "Using image folder for statistics report: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

                TEMP_FILE=$(mktemp)  # Fichier temporaire pour lister les fichiers

                for SYS_PATH in "$ROMS_DIR"/*; do
                    [ -d "$SYS_PATH" ] || continue
                    [ -r "$SYS_PATH" ] || {
                        echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
                        continue
                    }
                    SYS_NAME="${SYS_PATH##*/}"
                    case "$SYS_NAME" in
                        .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
                    esac

                    VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
                    [ -z "$VALID_EXTENSIONS" ] && {
                        echo "Skipping $SYS_NAME: No valid extensions defined." >> "$LOGS_PATH/Rom Inspector.txt"
                        continue
                    }

                    echo "Processing system: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
                    ROM_COUNT=0
                    COVER_COUNT=0
                    ROM_SIZE=0
                    COVER_SIZE=0
                    FILE_COUNT=0

                    # Lister tous les fichiers dans un fichier temporaire
                    > "$TEMP_FILE"
                    find "$SYS_PATH" -maxdepth 1 -type f > "$TEMP_FILE" 2>/dev/null

                    # Traiter les ROMs
                    while IFS= read -r ROM; do
                        [ -f "$ROM" ] && [ -r "$ROM" ] || continue
                        ROM_BASENAME="${ROM##*/}"
                        case "$ROM_BASENAME" in
                            .*|*.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
                        esac
                        if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                            ROM_COUNT=$((ROM_COUNT + 1))
                            SIZE=$(stat -c%s "$ROM" 2>/dev/null || echo 0)
                            if [ "$SIZE" -eq 0 ]; then
                                echo "Warning: Failed to get size for $ROM" >> "$LOGS_PATH/Rom Inspector.txt"
                                continue
                            fi
                            ROM_SIZE=$((ROM_SIZE + SIZE))
                            # Vérifier la couverture correspondante
                            COVER_FILE="$SYS_PATH/$image_folder/${ROM_BASENAME%.*}.png"
                            if [ -f "$COVER_FILE" ] && [ -r "$COVER_FILE" ]; then
                                COVER_COUNT=$((COVER_COUNT + 1))
                                COVER_SIZE_STAT=$(stat -c%s "$COVER_FILE" 2>/dev/null || echo 0)
                                if [ "$COVER_SIZE_STAT" -eq 0 ]; then
                                    echo "Warning: Failed to get size for $COVER_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                else
                                    COVER_SIZE=$((COVER_SIZE + COVER_SIZE_STAT))
                                fi
                            fi
                        fi
                        FILE_COUNT=$((FILE_COUNT + 1))
                        if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                            echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                            break
                        fi
                    done < "$TEMP_FILE"

                    # Skip systems with less than 1 MB of ROMs
                    MIN_ROM_SIZE=$((1 * 1024 * 1024))  # 1 MB en octets
                    if [ "$ROM_SIZE" -lt "$MIN_ROM_SIZE" ]; then
                        echo "Skipping $SYS_NAME: ROM size ($ROM_SIZE bytes) is less than 1 MB" >> "$LOGS_PATH/Rom Inspector.txt"
                        continue
                    fi

                    [ "$ROM_COUNT" -eq 0 ] && continue

                    if [ "$ROM_COUNT" -gt 0 ]; then
                        PERCENTAGE=$(( (COVER_COUNT * 100) / ROM_COUNT ))
                    else
                        PERCENTAGE=0
                    fi

                    TOTAL_SYSTEM_SIZE=$((ROM_SIZE + COVER_SIZE))
                    TOTAL_SYSTEM_SIZE_HUMAN=$(echo $TOTAL_SYSTEM_SIZE | awk '{printf "%.0f%s", $1/1024/1024, " MB"}')
                    echo "$SYS_NAME: $ROM_COUNT ROM(s)" >> "$STATS_FILE"
                    echo "$SYS_NAME: $PERCENTAGE% covers" >> "$STATS_FILE"
                    echo "$SYS_NAME: $TOTAL_SYSTEM_SIZE_HUMAN Size" >> "$STATS_FILE"
                    echo "" >> "$STATS_FILE"
                    TOTAL_ROM_COUNT=$((TOTAL_ROM_COUNT + ROM_COUNT))
                    TOTAL_COVER_COUNT=$((TOTAL_COVER_COUNT + COVER_COUNT))
                    TOTAL_SIZE=$((TOTAL_SIZE + TOTAL_SYSTEM_SIZE))
                    VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
                done

                rm -f "$TEMP_FILE" 2>/dev/null

                echo "Total ROMs: $TOTAL_ROM_COUNT" >> "$STATS_FILE"
                if [ "$TOTAL_ROM_COUNT" -gt 0 ]; then
                    TOTAL_PERCENTAGE=$(( (TOTAL_COVER_COUNT * 100) / TOTAL_ROM_COUNT ))
                else
                    TOTAL_PERCENTAGE=0
                fi
                TOTAL_SIZE_HUMAN=$(echo $TOTAL_SIZE | awk '{printf "%.0f%s", $1/1024/1024, " MB"}')
                echo "Total: $TOTAL_PERCENTAGE% covers" >> "$STATS_FILE"
                echo "Total: $TOTAL_SIZE_HUMAN Size" >> "$STATS_FILE"

                if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
                    echo "Error: No valid systems with ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "No systems with valid ROMs found." >> "$STATS_FILE"
                    show_message "Error: No valid systems found." 5
                    stop_loading
                    return 1
                fi

                cat "$STATS_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || {
                    echo "Error: Failed to read $STATS_FILE for logging" >> "$LOGS_PATH/Rom Inspector.txt"
                }

                show_message "Exported statistics to $STATS_FILE" 3
                stop_loading
                ;;
            *)
                echo "Error: Invalid selection in statistics menu: $selected_line" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Invalid selection." 5
                continue
                ;;
        esac
    done
    return 0
}

analyze_disk_usage() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="$DISK_USAGE_FILE"
    MAX_FILES=10000  # Global limit to avoid overload
    MIN_ROM_SIZE=$((1 * 1024 * 1024))  # 1 MB in bytes

    # Set up cleanup for temporary files
    trap 'rm -f "$TEMP_SYSTEMS_FILE" /tmp/disk_usage.menu /tmp/minui-output 2>/dev/null' EXIT

    # Determine if NextUI is used
    is_nextui=false
    image_folder=".media"
    if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
        is_nextui=true
    else
        image_folder=".res"
    fi
    echo "Using image folder for disk usage: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

    show_message "Analyzing disk usage..." forever
    LOADING_PID=$!

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== Disk Usage Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create disk_usage_report.txt." 5
        return 1
    }

    > /tmp/disk_usage.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/disk_usage.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create disk usage menu." 5
        return 1
    }

    TOTAL_SIZE=0
    VALID_SYSTEMS_FOUND=0
    TEMP_SYSTEMS_FILE=$(mktemp)  # Temporary file to store system sizes

    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || {
            echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && {
            echo "Skipping $SYS_NAME: No valid extensions defined." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }

        echo "Analyzing disk usage for system: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
        ROM_SIZE=0
        COVER_SIZE=0
        FILE_COUNT=0

        # Calculate ROMs size
        while IFS= read -r -d '' ROM; do
            ROM_BASENAME="${ROM##*/}"
            case "$ROM_BASENAME" in
                .*|*.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) continue ;;
            esac
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                SIZE=$(stat -c%s "$ROM" 2>/dev/null || echo 0)
                [ "$SIZE" -eq 0 ] && {
                    echo "Warning: Failed to get size for $ROM" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                }
                ROM_SIZE=$((ROM_SIZE + SIZE))
                FILE_COUNT=$((FILE_COUNT + 1))
                [ "$FILE_COUNT" -gt "$MAX_FILES" ] && {
                    echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                    break
                }
            fi
        done < <(find "$SYS_PATH" -maxdepth 1 -type f -print0)

        # Skip systems with less than 1 MB of ROMs
        if [ "$ROM_SIZE" -lt "$MIN_ROM_SIZE" ]; then
            echo "Skipping $SYS_NAME: ROM size ($ROM_SIZE bytes) is less than 1 MB" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        # Calculate covers size
        MEDIA_PATH="$SYS_PATH/$image_folder"
        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            while IFS= read -r -d '' COVER; do
                SIZE=$(stat -c%s "$COVER" 2>/dev/null || echo 0)
                [ "$SIZE" -eq 0 ] && {
                    echo "Warning: Failed to get size for $COVER" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                }
                COVER_SIZE=$((COVER_SIZE + SIZE))
            done < <(find "$MEDIA_PATH" -maxdepth 1 -type f -name "*.png" -print0)
        fi

        TOTAL_SYSTEM_SIZE=$((ROM_SIZE + COVER_SIZE))
        if [ "$TOTAL_SYSTEM_SIZE" -gt 0 ]; then
            ROM_SIZE_HUMAN=$(echo $ROM_SIZE | awk '{printf "%.1f", $1/1024/1024}')
            COVER_SIZE_HUMAN=$(echo $COVER_SIZE | awk '{printf "%.1f", $1/1024/1024}')
            TOTAL_SYSTEM_SIZE_HUMAN=$(echo $TOTAL_SYSTEM_SIZE | awk '{printf "%.1f", $1/1024/1024}')
            echo "$SYS_NAME - ${TOTAL_SYSTEM_SIZE_HUMAN} Mb" >> /tmp/disk_usage.menu
            echo "$SYS_NAME|$ROM_SIZE_HUMAN|$COVER_SIZE_HUMAN|$TOTAL_SYSTEM_SIZE_HUMAN" >> "$TEMP_SYSTEMS_FILE"
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_SIZE=$((TOTAL_SIZE + TOTAL_SYSTEM_SIZE))

            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "ROMs Size: ${ROM_SIZE_HUMAN} Mb" >> "$OUTPUT_FILE"
            echo "Covers Size: ${COVER_SIZE_HUMAN} Mb" >> "$OUTPUT_FILE"
            echo "Total Size: ${TOTAL_SYSTEM_SIZE_HUMAN} Mb" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done

    TOTAL_SIZE_HUMAN=$(echo $TOTAL_SIZE | awk '{printf "%.1f", $1/1024/1024}')
    echo "Total Disk Usage: ${TOTAL_SIZE_HUMAN} Mb" >> /tmp/disk_usage.menu
    echo "Total Disk Usage: ${TOTAL_SIZE_HUMAN} Mb" >> "$OUTPUT_FILE"

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with valid ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "No valid systems found." 5
        return 1
    fi

    echo "Disk usage analysis completed. Systems found: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Contents of /tmp/disk_usage.menu:" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/disk_usage.menu >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "Error: Failed to read /tmp/disk_usage.menu" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ ! -s /tmp/disk_usage.menu ]; then
        echo "Error: /tmp/disk_usage.menu is empty" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: No systems available to display." 5
        return 1
    fi

    while true; do
        # Ensure menu file is intact before launching
        if [ ! -s /tmp/disk_usage.menu ]; then
            echo "Error: /tmp/disk_usage.menu is empty or missing" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Menu file is corrupted." 5
            return 1
        fi

        # Clear previous minui-output to prevent stale data
        rm -f /tmp/minui-output 2>/dev/null

        echo "Launching minui-list for disk usage menu" >> "$LOGS_PATH/Rom Inspector.txt"
        minui-list --disable-auto-sleep \
            --item-key disk_usage \
            --file /tmp/disk_usage.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Disk Usage per System" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        echo "minui-list exited with code: $MINUI_EXIT_CODE" >> "$LOGS_PATH/Rom Inspector.txt"
        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled disk usage menu or minui-list failed (exit code: $MINUI_EXIT_CODE)" >> "$LOGS_PATH/Rom Inspector.txt"
            # Option 1: Return to parent menu (current behavior, matches log)
            return 0
            # Option 2: Stay in system list menu (uncomment to use)
            # continue
        fi

        if [ ! -f /tmp/minui-output ]; then
            echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        echo "Selected index: $idx" >> "$LOGS_PATH/Rom Inspector.txt"
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/disk_usage.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')
        echo "Selected system: $selected_sys" >> "$LOGS_PATH/Rom Inspector.txt"

        if [ "$selected_sys" = "Total Disk Usage" ]; then
            show_message "Total Disk Usage: ${TOTAL_SIZE_HUMAN} Mb" 5 || {
                echo "Warning: show_message failed for Total Disk Usage" >> "$LOGS_PATH/Rom Inspector.txt"
            }
            continue
        fi

        system_details=$(grep "^$selected_sys|" "$TEMP_SYSTEMS_FILE" 2>/dev/null)
        if [ -z "$system_details" ]; then
            echo "Error: No details found for $selected_sys in $TEMP_SYSTEMS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        ROM_SIZE_HUMAN=$(echo "$system_details" | cut -d'|' -f2)
        COVER_SIZE_HUMAN=$(echo "$system_details" | cut -d'|' -f3)
        TOTAL_SIZE_HUMAN=$(echo "$system_details" | cut -d'|' -f4)

        # Use printf to format the message with actual newlines (unchanged as requested)
        DETAIL_MESSAGE=$(printf "%s:\nROMs: %s Mb\nCovers: %s Mb\nTotal: %s Mb" \
            "$selected_sys" "$ROM_SIZE_HUMAN" "$COVER_SIZE_HUMAN" "$TOTAL_SIZE_HUMAN")
        echo "Attempting to display details for $selected_sys: $DETAIL_MESSAGE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "$DETAIL_MESSAGE" 5 || {
            echo "Warning: show_message failed to display details for $selected_sys" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        echo "Displayed details for $selected_sys: ROMs: $ROM_SIZE_HUMAN Mb, Covers: $COVER_SIZE_HUMAN Mb, Total: $TOTAL_SIZE_HUMAN Mb" >> "$LOGS_PATH/Rom Inspector.txt"
    done

    show_message "Disk usage report saved to $OUTPUT_FILE" 5
    return 0
}

list_orphaned_files() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="$ORPHANED_FILES_FILE"
    MAX_FILES=1000  # Global limit to avoid overload

    # Determine if NextUI is used
    is_nextui=false
    image_folder=".media"
    if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
        is_nextui=true
    else
        image_folder=".res"
    fi
    echo "Using image folder for orphaned files: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

    show_message "Scanning for orphaned files..." forever
    LOADING_PID=$!

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== Orphaned Files Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create orphaned_files.txt." 5
        return 1
    }

    > /tmp/roms_orphaned.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/roms_orphaned.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create menu file." 5
        return 1
    }
    VALID_SYSTEMS_FOUND=0
    TOTAL_ORPHANED_COUNT=0

    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || {
            echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && {
            echo "Skipping $SYS_NAME: No valid extensions defined." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }

        echo "Scanning system for orphaned files: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
        MEDIA_PATH="$SYS_PATH/$image_folder"
        ORPHANED_COUNT=0
        TEMP_FILE=$(mktemp)
        FILE_COUNT=0

        # Check all files in the system directory (not just media folder)
        for FILE in "$SYS_PATH"/*; do
            [ -f "$FILE" ] || continue
            FILE_BASENAME="${FILE##*/}"
            # Skip bg.png and OUTPUT_FILE
            [ "$FILE_BASENAME" = "bg.png" ] && continue
            [ "$FILE" = "$OUTPUT_FILE" ] && continue
            FILE_NAME="${FILE_BASENAME%.*}"
            FILE_EXT="${FILE_BASENAME##*.}"
            
            # Skip valid ROM files
            is_valid_extension "$FILE_BASENAME" "$VALID_EXTENSIONS" && continue
            
            # Skip known system files (excluding .txt)
            case "$FILE_BASENAME" in
                *.miyoocmd|*.db|*.json|*.config|*.cfg|*.ini|*.dat|*.backup.dat|*.txt) continue ;;
                *.cue) 
                    # Allow .cue for PlayStation
                    [ "$SYS_NAME" = "Sony PlayStation (PS)" ] && continue ;;
            esac

            # Skip if this is a valid ROM file (without extension)
            ROM_EXISTS=false
            for EXT in $VALID_EXTENSIONS; do
                if [ -f "$SYS_PATH/$FILE_NAME.$EXT" ]; then
                    ROM_EXISTS=true
                    break
                fi
            done
            [ "$ROM_EXISTS" = true ] && continue

            ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
            echo "$FILE_BASENAME" >> "$TEMP_FILE"
            echo "Orphaned file: $FILE_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
            
            FILE_COUNT=$((FILE_COUNT + 1))
            if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
        done

        # Also check media folder for orphaned images
        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            for COVER in "$MEDIA_PATH"/*; do
                [ -f "$COVER" ] || continue
                COVER_BASENAME="${COVER##*/}"
                # Skip bg.png
                [ "$COVER_BASENAME" = "bg.png" ] && continue
                COVER_NAME="${COVER_BASENAME%.*}"
                ROM_EXISTS=false

                for EXT in $VALID_EXTENSIONS; do
                    if [ -f "$SYS_PATH/$COVER_NAME.$EXT" ]; then
                        ROM_EXISTS=true
                        break
                    fi
                done

                if [ "$ROM_EXISTS" = false ]; then
                    ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
                    echo "$COVER_BASENAME" >> "$TEMP_FILE"
                    echo "Orphaned cover: $COVER_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                fi
                FILE_COUNT=$((FILE_COUNT + 1))
                if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                    echo "Warning: Too many files in $SYS_NAME media, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                    break
                fi
            done
        fi

        if [ "$ORPHANED_COUNT" -gt 0 ]; then
            if [ "$ORPHANED_COUNT" -eq 1 ]; then
                echo "$SYS_NAME - $ORPHANED_COUNT orphaned file" >> /tmp/roms_orphaned.menu
                echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
                echo "Orphaned file: $ORPHANED_COUNT" >> "$OUTPUT_FILE"
            else
                echo "$SYS_NAME - $ORPHANED_COUNT orphaned files" >> /tmp/roms_orphaned.menu
                echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
                echo "Orphaned files: $ORPHANED_COUNT" >> "$OUTPUT_FILE"
            fi
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_ORPHANED_COUNT=$((TOTAL_ORPHANED_COUNT + ORPHANED_COUNT))
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            # Create .cache directory if it doesn't exist
            mkdir -p "$SYS_PATH/.cache" 2>/dev/null || {
                echo "Error: Failed to create directory $SYS_PATH/.cache" >> "$LOGS_PATH/Rom Inspector.txt"
                rm -f "$TEMP_FILE"
                continue
            }
            mv "$TEMP_FILE" "$SYS_PATH/.cache/orphaned_files.txt" 2>/dev/null || {
                echo "Error: Failed to save orphaned files list to $SYS_PATH/.cache/orphaned_files.txt" >> "$LOGS_PATH/Rom Inspector.txt"
                rm -f "$TEMP_FILE"
            }
        else
            echo "No orphaned files for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
            rm -f "$TEMP_FILE"
        fi
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with orphaned files found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No orphaned files found." >> "$OUTPUT_FILE"
        show_message "No orphaned files found." 5
        return 0
    fi

    echo "Systems with orphaned files: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total orphaned files: $TOTAL_ORPHANED_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/roms_orphaned.menu >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "Error: Failed to read /tmp/roms_orphaned.menu" >> "$LOGS_PATH/Rom Inspector.txt"

    # Add option to delete all orphaned files
    echo "Delete all orphaned files ($TOTAL_ORPHANED_COUNT files)" >> /tmp/roms_orphaned.menu

    if [ ! -s /tmp/roms_orphaned.menu ]; then
        echo "Error: /tmp/roms_orphaned.menu is empty or does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to generate systems menu." 5
        return 1
    fi

    while true; do
        minui-list --disable-auto-sleep \
            --item-key orphaned_files \
            --file /tmp/roms_orphaned.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Orphaned Files" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled systems menu (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi
        if [ ! -f /tmp/minui-output ]; then
            echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Failed to read menu output." 5
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi

        # Check if the user selected the "Delete all orphaned files" option
        total_lines=$(wc -l < /tmp/roms_orphaned.menu)
        if [ "$idx" -eq "$((total_lines - 1))" ]; then
            echo "User selected to delete all orphaned files" >> "$LOGS_PATH/Rom Inspector.txt"

            # Confirm deletion of all orphaned files
            if ! confirm_deletion "all $TOTAL_ORPHANED_COUNT orphaned files" "all orphaned files"; then
                echo "Deletion of all orphaned files cancelled." >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Deletion of all orphaned files cancelled." 5
                continue
            fi

            show_message "Deleting orphaned files..." forever
            LOADING_PID=$!

            DELETED_COUNT=0
            FAILED_COUNT=0

            # Delete all orphaned files across all systems
            for SYS_PATH in "$ROMS_DIR"/*; do
                [ -d "$SYS_PATH" ] || continue
                SYS_NAME="${SYS_PATH##*/}"
                case "$SYS_NAME" in
                    .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
                esac

                ORPHANED_FILES_FILE="$SYS_PATH/.cache/orphaned_files.txt"
                if [ -f "$ORPHANED_FILES_FILE" ] && [ -s "$ORPHANED_FILES_FILE" ]; then
                    echo "Processing orphaned files for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
                    while IFS= read -r FILE_BASENAME; do
                        # Skip empty or invalid lines
                        [ -z "$FILE_BASENAME" ] && continue
                        if [ -f "$SYS_PATH/$image_folder/$FILE_BASENAME" ]; then
                            FILE_TO_DELETE="$SYS_PATH/$image_folder/$FILE_BASENAME"
                        else
                            FILE_TO_DELETE="$SYS_PATH/$FILE_BASENAME"
                        fi
                        # Ensure the file exists before attempting deletion
                        if [ -f "$FILE_TO_DELETE" ]; then
                            if rm -f "$FILE_TO_DELETE" 2>/dev/null; then
                                echo "Successfully deleted: $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                                echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
                                echo "- Deleted: $FILE_BASENAME" >> "$OUTPUT_FILE"
                                DELETED_COUNT=$((DELETED_COUNT + 1))
                            else
                                echo "Error: Failed to delete $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                                FAILED_COUNT=$((FAILED_COUNT + 1))
                            fi
                        else
                            echo "Error: File $FILE_TO_DELETE does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    done < "$ORPHANED_FILES_FILE"

                    # Remove the orphaned files list
                    rm -f "$ORPHANED_FILES_FILE" 2>/dev/null
                fi
            done

            stop_loading

            # Update counters and rebuild the menu
            VALID_SYSTEMS_FOUND=0
            TOTAL_ORPHANED_COUNT=0
            > /tmp/roms_orphaned.menu

            # Re-scan systems to rebuild the menu
            for SYS_PATH in "$ROMS_DIR"/*; do
                [ -d "$SYS_PATH" ] || continue
                SYS_NAME="${SYS_PATH##*/}"
                case "$SYS_NAME" in
                    .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
                esac

                VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
                [ -z "$VALID_EXTENSIONS" ] && continue

                ORPHANED_COUNT=0
                TEMP_FILE=$(mktemp)

                # Check system directory
                for FILE in "$SYS_PATH"/*; do
                    [ -f "$FILE" ] || continue
                    FILE_BASENAME="${FILE##*/}"
                    [ "$FILE_BASENAME" = "bg.png" ] && continue
                    [ "$FILE" = "$OUTPUT_FILE" ] && continue
                    FILE_NAME="${FILE_BASENAME%.*}"
                    FILE_EXT="${FILE_BASENAME##*.}"

                    is_valid_extension "$FILE_BASENAME" "$VALID_EXTENSIONS" && continue
                    case "$FILE_BASENAME" in
                        *.miyoocmd|*.db|*.json|*.config|*.cfg|*.ini|*.dat|*.backup.dat|*.txt) continue ;;
                        *.cue)
                            [ "$SYS_NAME" = "Sony PlayStation (PS)" ] && continue ;;
                    esac

                    ROM_EXISTS=false
                    for EXT in $VALID_EXTENSIONS; do
                        if [ -f "$SYS_PATH/$FILE_NAME.$EXT" ]; then
                            ROM_EXISTS=true
                            break
                        fi
                    done
                    [ "$ROM_EXISTS" = true ] && continue

                    ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
                    echo "$FILE_BASENAME" >> "$TEMP_FILE"
                done

                # Check media folder
                if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
                    for COVER in "$MEDIA_PATH"/*; do
                        [ -f "$COVER" ] || continue
                        COVER_BASENAME="${COVER##*/}"
                        [ "$COVER_BASENAME" = "bg.png" ] && continue
                        COVER_NAME="${COVER_BASENAME%.*}"
                        ROM_EXISTS=false

                        for EXT in $VALID_EXTENSIONS; do
                            if [ -f "$SYS_PATH/$COVER_NAME.$EXT" ]; then
                                ROM_EXISTS=true
                                break
                            fi
                        done

                        if [ "$ROM_EXISTS" = false ]; then
                            ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
                            echo "$COVER_BASENAME" >> "$TEMP_FILE"
                        fi
                    done
                fi

                if [ "$ORPHANED_COUNT" -gt 0 ]; then
                    if [ "$ORPHANED_COUNT" -eq 1 ]; then
                        echo "$SYS_NAME - $ORPHANED_COUNT orphaned file" >> /tmp/roms_orphaned.menu
                        echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
                        echo "Orphaned file: $ORPHANED_COUNT" >> "$OUTPUT_FILE"
                    else
                        echo "$SYS_NAME - $ORPHANED_COUNT orphaned files" >> /tmp/roms_orphaned.menu
                        echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
                        echo "Orphaned files: $ORPHANED_COUNT" >> "$OUTPUT_FILE"
                    fi
                    VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
                    TOTAL_ORPHANED_COUNT=$((TOTAL_ORPHANED_COUNT + ORPHANED_COUNT))
                    cat "$TEMP_FILE" >> "$OUTPUT_FILE"
                    echo "" >> "$OUTPUT_FILE"
                    # Create .cache directory if it doesn't exist
                    mkdir -p "$SYS_PATH/.cache" 2>/dev/null || {
                        echo "Error: Failed to create directory $SYS_PATH/.cache" >> "$LOGS_PATH/Rom Inspector.txt"
                        rm -f "$TEMP_FILE"
                        continue
                    }
                    mv "$TEMP_FILE" "$SYS_PATH/.cache/orphaned_files.txt" 2>/dev/null || {
                        echo "Error: Failed to save orphaned files list to $SYS_PATH/.cache/orphaned_files.txt" >> "$LOGS_PATH/Rom Inspector.txt"
                        rm -f "$TEMP_FILE"
                    }
                else
                    rm -f "$TEMP_FILE"
                fi
            done

            # Add the "Delete all" option again if there are still orphaned files
            if [ "$VALID_SYSTEMS_FOUND" -gt 0 ]; then
                echo "Delete all orphaned files ($TOTAL_ORPHANED_COUNT files)" >> /tmp/roms_orphaned.menu
            fi

            if [ "$DELETED_COUNT" -gt 0 ]; then
                echo "Successfully deleted $DELETED_COUNT orphaned files." >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Successfully deleted $DELETED_COUNT orphaned files." 5
            fi
            if [ "$FAILED_COUNT" -gt 0 ]; then
                echo "Failed to delete $FAILED_COUNT orphaned files." >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Failed to delete $FAILED_COUNT orphaned files." 5
            fi
            if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
                echo "No systems with orphaned files remain." >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "No systems with orphaned files remain." 5
                return 0
            fi

            echo "Remaining systems with orphaned files: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
            echo "Remaining total orphaned files: $TOTAL_ORPHANED_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/roms_orphaned.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        ORPHANED_FILES_FILE="$SYS_PATH/.cache/orphaned_files.txt"

        if [ ! -f "$ORPHANED_FILES_FILE" ] || [ ! -s "$ORPHANED_FILES_FILE" ]; then
            echo "Error: Orphaned files list not found or empty for $selected_sys: $ORPHANED_FILES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No orphaned files found for $selected_sys." 5
            continue
        fi

        # Log the contents of the orphaned files list
        echo "Orphaned files list contents for $selected_sys:" >> "$LOGS_PATH/Rom Inspector.txt"
        cat "$ORPHANED_FILES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"

        while true; do
            minui-list --disable-auto-sleep \
                --item-key orphaned_file_items \
                --file "$ORPHANED_FILES_FILE" \
                --format text \
                --cancel-text "BACK" \
                --title "Orphaned Files for $selected_sys" \
                --write-location /tmp/minui-output \
                --write-value state
            MINUI_EXIT_CODE=$?

            echo "minui-list exit code for orphaned files: $MINUI_EXIT_CODE" >> "$LOGS_PATH/Rom Inspector.txt"

            if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled orphaned files menu for $selected_sys (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
            if [ ! -f /tmp/minui-output ]; then
                echo "Error: minui-list output file /tmp/minui-output not found for orphaned files" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to read menu output." 5
                break
            fi

            file_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            echo "Selected file index: $file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
            if [ "$file_idx" = "null" ] || [ -z "$file_idx" ] || [ "$file_idx" = "-1" ]; then
                echo "Invalid or no selection for orphaned file: idx=$file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            selected_file=$(sed -n "$((file_idx + 1))p" "$ORPHANED_FILES_FILE" 2>/dev/null)
            echo "Selected orphaned file: $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
            if [ -z "$selected_file" ]; then
                echo "Error: No file selected or invalid index: $file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Invalid file selection." 5
                break
            fi

            # Check if file is in media folder or system folder
            if [ -f "$SYS_PATH/$image_folder/$selected_file" ]; then
                FILE_TO_DELETE="$SYS_PATH/$image_folder/$selected_file"
            else
                FILE_TO_DELETE="$SYS_PATH/$selected_file"
            fi
            
            echo "Attempting to delete: $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"

            if confirm_deletion "$FILE_TO_DELETE" "orphaned file"; then
                show_message "Deleting orphaned files..." forever
                LOADING_PID=$!

                if [ -f "$FILE_TO_DELETE" ] && rm -f "$FILE_TO_DELETE" 2>/dev/null; then
                    stop_loading
                    echo "Successfully deleted orphaned file: $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "System: $selected_sys" >> "$OUTPUT_FILE"
                    echo "- Deleted: $selected_file" >> "$OUTPUT_FILE"
                    show_message "Deleted: $selected_file" 3
                    # Remove the deleted file from the list
                    grep -v "^$selected_file$" "$ORPHANED_FILES_FILE" > "${ORPHANED_FILES_FILE}.tmp" && mv "${ORPHANED_FILES_FILE}.tmp" "$ORPHANED_FILES_FILE"
                    # Update the menu with the new count
                    if [ -s "$ORPHANED_FILES_FILE" ]; then
                        NEW_ORPHANED_COUNT=$(wc -l < "$ORPHANED_FILES_FILE")
                        echo "Updated orphaned count for $selected_sys: $NEW_ORPHANED_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
                        if [ "$NEW_ORPHANED_COUNT" -eq 1 ]; then
                            sed -i "/^$selected_sys - /c\\$selected_sys - $NEW_ORPHANED_COUNT orphaned file" /tmp/roms_orphaned.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                        else
                            sed -i "/^$selected_sys - /c\\$selected_sys - $NEW_ORPHANED_COUNT orphaned files" /tmp/roms_orphaned.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                        fi
                    else
                        echo "No more orphaned files for $selected_sys, removing from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                        sed -i "/^$selected_sys - /d" /tmp/roms_orphaned.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                        rm -f "$ORPHANED_FILES_FILE"
                        # Update VALID_SYSTEMS_FOUND and check if menu is empty
                        VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND - 1))
                        if [ "$VALID_SYSTEMS_FOUND" -eq 0 ] || [ ! -s /tmp/roms_orphaned.menu ]; then
                            echo "No systems with orphaned files remain" >> "$LOGS_PATH/Rom Inspector.txt"
                            show_message "No systems with orphaned files remain." 5
                            return 0
                        fi
                        break
                    fi
                else
                    stop_loading
                    echo "Error: Failed to delete $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to delete $selected_file." 5
                fi
            else
                echo "Deletion cancelled for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Deletion cancelled for $selected_file" 3
            fi
        done
    done

    echo "Exiting list_orphaned_files function" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Orphaned files report saved to $OUTPUT_FILE" 5
    return 0
}

verify_cover_resolutions() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="/mnt/SDCARD/cover_resolutions_report.txt"
    MAX_FILES=1000  # Global limit to avoid overload

    # Determine if NextUI is used
    is_nextui=false
    image_folder=".media"
    if [ "$IS_NEXT" = "true" ] || [ "$IS_NEXT" = "yes" ] || [ -f "$USERDATA_PATH/minuisettings.txt" ]; then
        is_nextui=true
    else
        image_folder=".res"
    fi
    echo "Using image folder for cover resolutions: $image_folder (is_nextui: $is_nextui)" >> "$LOGS_PATH/Rom Inspector.txt"

    show_message "Verifying cover resolutions..." forever
    LOADING_PID=$!

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== Cover Resolutions Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create cover_resolutions_report.txt." 5
        return 1
    }

    > /tmp/cover_resolutions.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/cover_resolutions.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create menu file." 5
        return 1
    }
    VALID_SYSTEMS_FOUND=0
    TOTAL_PROBLEMATIC_COVERS=0

    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || {
            echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") continue ;;
        esac

        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        [ -z "$VALID_EXTENSIONS" ] && {
            echo "Skipping $SYS_NAME: No valid extensions defined." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }

        MIN_RESOLUTION=$(get_min_cover_resolution "$SYS_NAME")
        echo "Verifying cover resolutions for system: $SYS_NAME (Minimum resolution: ${MIN_RESOLUTION}x${MIN_RESOLUTION})" >> "$LOGS_PATH/Rom Inspector.txt"
        MEDIA_PATH="$SYS_PATH/$image_folder"
        PROBLEMATIC_COUNT=0
        TEMP_FILE=$(mktemp)
        FILE_COUNT=0

        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            for COVER in "$MEDIA_PATH"/*.png; do
                [ -f "$COVER" ] && [ -r "$COVER" ] || continue
                COVER_BASENAME="${COVER##*/}"

                # Extract width and height from PNG IHDR chunk
                width=$((16#$(dd if="$COVER" bs=1 skip=16 count=4 2>/dev/null | xxd -p | tr -d '\n')))
                height=$((16#$(dd if="$COVER" bs=1 skip=20 count=4 2>/dev/null | xxd -p | tr -d '\n')))

                # Fallback to file command if dd/xxd method fails
                if [ -z "$width" ] || [ -z "$height" ] || [ "$width" -eq 0 ] || [ "$height" -eq 0 ]; then
                    resolution=$(file "$COVER" 2>/dev/null | grep -oE '[0-9]+ x [0-9]+')
                    if [ -n "$resolution" ]; then
                        width=$(echo "$resolution" | cut -d' ' -f1)
                        height=$(echo "$resolution" | cut -d' ' -f3)
                        echo "Resolution via file command: $width x $height" >> "$LOGS_PATH/Rom Inspector.txt"
                    else
                        echo "Warning: Failed to get resolution for $COVER" >> "$LOGS_PATH/Rom Inspector.txt"
                        continue
                    fi
                fi

                RESOLUTION="$width x $height"
                WIDTH=$width
                HEIGHT=$height

                # Debug output for resolution detection
                echo "Debug: $COVER_BASENAME - detected resolution: $width x $height" >> "$LOGS_PATH/Rom Inspector.txt"

                # Check for problematic resolutions
                if [ "$WIDTH" -lt "$MIN_RESOLUTION" ] || [ "$HEIGHT" -lt "$MIN_RESOLUTION" ] || \
                   [ "$WIDTH" -gt 2000 ] || [ "$HEIGHT" -gt 2000 ] || \
                   [ $((WIDTH * 100 / HEIGHT)) -lt 50 ] || [ $((WIDTH * 100 / HEIGHT)) -gt 200 ]; then
                    PROBLEMATIC_COUNT=$((PROBLEMATIC_COUNT + 1))
                    echo "$COVER_BASENAME - $RESOLUTION" >> "$TEMP_FILE"
                    echo "Problematic cover: $COVER_BASENAME ($RESOLUTION)" >> "$LOGS_PATH/Rom Inspector.txt"
                fi
                
                FILE_COUNT=$((FILE_COUNT + 1))
                if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                    echo "Warning: Too many cover files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                    break
                fi
            done
        fi

        if [ "$PROBLEMATIC_COUNT" -gt 0 ]; then
            [ "$PROBLEMATIC_COUNT" -eq 1 ] && COVER_TEXT="cover" || COVER_TEXT="covers"
            echo "$SYS_NAME - $PROBLEMATIC_COUNT problematic $COVER_TEXT" >> /tmp/cover_resolutions.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_PROBLEMATIC_COVERS=$((TOTAL_PROBLEMATIC_COVERS + PROBLEMATIC_COUNT))
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Problematic $COVER_TEXT: $PROBLEMATIC_COUNT" >> "$OUTPUT_FILE"
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            mv "$TEMP_FILE" "$SYS_PATH/.cache/problematic_covers.txt" 2>/dev/null || {
                echo "Warning: Failed to save problematic $COVER_TEXT list to $SYS_PATH/.cache/problematic_covers.txt" >> "$LOGS_PATH/Rom Inspector.txt"
                rm -f "$TEMP_FILE"
            }
        else
            echo "No problematic covers for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
            rm -f "$TEMP_FILE"
        fi
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with problematic cover resolutions found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No problematic covers found." >> "$OUTPUT_FILE"
        show_message "No problematic covers found." 5
        return 0
    fi

    [ "$TOTAL_PROBLEMATIC_COVERS" -eq 1 ] && COVER_TEXT="cover" || COVER_TEXT="covers"
    echo "Systems with problematic $COVER_TEXT: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total problematic $COVER_TEXT: $TOTAL_PROBLEMATIC_COVERS" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/cover_resolutions.menu >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "Error: Failed to read /tmp/cover_resolutions.menu" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ ! -s /tmp/cover_resolutions.menu ]; then
        echo "Error: /tmp/cover_resolutions.menu is empty or does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to generate systems menu." 5
        return 1
    fi

    while true; do
        minui-list --disable-auto-sleep \
            --item-key cover_resolutions \
            --file /tmp/cover_resolutions.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Problematic Cover Resolutions" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled systems menu (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi
        if [ ! -f /tmp/minui-output ]; then
            echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Failed to read menu output." 5
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/cover_resolutions.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        PROBLEMATIC_COVERS_FILE="$SYS_PATH/.cache/problematic_covers.txt"

        if [ ! -f "$PROBLEMATIC_COVERS_FILE" ] || [ ! -s "$PROBLEMATIC_COVERS_FILE" ]; then
            echo "Error: Problematic covers list not found or empty for $selected_sys: $PROBLEMATIC_COVERS_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No problematic covers found for $selected_sys." 5
            continue
        fi

        while true; do
            minui-list --disable-auto-sleep \
                --item-key problematic_cover_items \
                --file "$PROBLEMATIC_COVERS_FILE" \
                --format text \
                --cancel-text "BACK" \
                --title "Problematic Covers for $selected_sys" \
                --write-location /tmp/minui-output \
                --write-value state
            MINUI_EXIT_CODE=$?

            stop_loading

            if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled problematic covers menu for $selected_sys (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
            if [ ! -f /tmp/minui-output ]; then
                echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to read menu output." 5
                break
            fi

            file_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$file_idx" != "null" ] && [ -n "$file_idx" ] && [ "$file_idx" != "-1" ]; then
                selected_cover=$(sed -n "$((file_idx + 1))p" "$PROBLEMATIC_COVERS_FILE" 2>/dev/null | cut -d' ' -f1)
                echo "User selected cover $selected_cover for $selected_sys with button A, no action taken (SELECT ignored)" >> "$LOGS_PATH/Rom Inspector.txt"
                continue
            else
                echo "User viewed problematic covers for $selected_sys, no valid selection made" >> "$LOGS_PATH/Rom Inspector.txt"
            fi
        done
    done

    [ "$TOTAL_PROBLEMATIC_COVERS" -eq 1 ] && COVER_TEXT="cover" || COVER_TEXT="covers"
    echo "Exiting verify_cover_resolutions function" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Cover resolutions report saved to $OUTPUT_FILE ($TOTAL_PROBLEMATIC_COVERS problematic $COVER_TEXT)." 5
    return 0
}

check_roms_names() {
    ROMS_DIR="/mnt/SDCARD/Roms"
    OUTPUT_FILE="$ROM_NAMES_FILE"
    MAX_FILES=3000  # Global limit to avoid overload

    show_message "Scanning ROMs.. This may take a moment!" forever
    LOADING_PID=$!

    # Clear previous log
    echo "=== ROM Names Inspection - New Run ===" > "$LOGS_PATH/Rom Inspector.txt"

    if [ ! -d "$ROMS_DIR" ] || [ ! -r "$ROMS_DIR" ]; then
        stop_loading
        echo "Error: ROMS_DIR ($ROMS_DIR) does not exist or is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: ROMs directory not found or not readable." 5
        return 1
    fi

    if [ ! -w "/mnt/SDCARD" ]; then
        stop_loading
        echo "Error: No write access to /mnt/SDCARD." >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Cannot write to /mnt/SDCARD." 5
        return 1
    fi

    echo "=== ROM Names Report ===" > "$OUTPUT_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt" || {
        stop_loading
        echo "Error: Failed to initialize $OUTPUT_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create rom_names_report.txt." 5
        return 1
    }

    > /tmp/rom_names.menu || {
        stop_loading
        echo "Error: Failed to create /tmp/rom_names.menu" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to create menu file." 5
        return 1
    }

    VALID_SYSTEMS_FOUND=0
    TOTAL_PROBLEMATIC_NAMES=0
    # Simplified pattern to catch special characters and multiple spaces
    PROBLEMATIC_PATTERN='[][#$%*+?=|<>@;{}"]|^\s+|\s{2,}'

    # Process each system directory
    for SYS_PATH in "$ROMS_DIR"/*; do
        [ -d "$SYS_PATH" ] || continue
        [ -r "$SYS_PATH" ] || {
            echo "Warning: Directory $SYS_PATH is not readable." >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        }
        
        SYS_NAME="${SYS_PATH##*/}"
        case "$SYS_NAME" in
            .media|.res|*.backup|"0) BitPal (BITPAL)"|"0) Favorites (CUSTOM)") 
                echo "Skipping system: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
                continue 
                ;;
        esac

        echo "=== Processing System: $SYS_NAME ===" >> "$LOGS_PATH/Rom Inspector.txt"
        
        # Get valid extensions with fallback
        VALID_EXTENSIONS=$(get_valid_extensions "$SYS_NAME")
        if [ -z "$VALID_EXTENSIONS" ]; then
            VALID_EXTENSIONS="zip|7z|gba|gb|gbc|nes|sfc|smc|md|gen|gg|sms|pce|iso|cue|bin|ngp|ngc|v64|z64|n64|a26|col|cpr|d64|t64|tap|prg|p00|cr|dsk|j64|cdt|scl|trd|sc|fds|lnx|msa|st|dim|ipf|ctr|32x|a52|jag|wsc|pce|sg|mv|cpc|cdt|dsk|rom"
            echo "Using fallback extensions for $SYS_NAME: $VALID_EXTENSIONS" >> "$LOGS_PATH/Rom Inspector.txt"
        else
            echo "Using system extensions for $SYS_NAME: $VALID_EXTENSIONS" >> "$LOGS_PATH/Rom Inspector.txt"
        fi

        PROBLEMATIC_COUNT=0
        TEMP_FILE=$(mktemp)
        FILE_COUNT=0

        # Find all ROMs in the system directory and process them safely
        while IFS= read -r ROM; do
            [ -f "$ROM" ] && [ -r "$ROM" ] || {
                echo "DEBUG: Skipping unreadable file: $ROM" >> "$LOGS_PATH/Rom Inspector.txt"
                continue
            }
            ROM_BASENAME="${ROM##*/}"
            
            # Skip hidden files and specific extensions
            case "$ROM_BASENAME" in
                .*) 
                    echo "DEBUG: Skipping hidden file: $ROM_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue 
                    ;;
                *.txt|*.dat|*.backup|*.m3u|*.cue|*.sh|*.ttf|*.png|*.p8.png) 
                    echo "DEBUG: Skipping excluded extension: $ROM_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue 
                    ;;
            esac
            
            if is_valid_extension "$ROM_BASENAME" "$VALID_EXTENSIONS"; then
                ROM_NAME="${ROM_BASENAME%.*}"
                
                if echo "$ROM_NAME" | grep -E "$PROBLEMATIC_PATTERN" >/dev/null; then
                    PROBLEMATIC_COUNT=$((PROBLEMATIC_COUNT + 1))
                    echo "$ROM_BASENAME" >> "$TEMP_FILE"
                    echo "PROBLEMATIC: $ROM_BASENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                fi
                
                FILE_COUNT=$((FILE_COUNT + 1))
                if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                    echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                    break
                fi
            fi
        done < <(find "$SYS_PATH" -maxdepth 1 -type f)

        if [ "$PROBLEMATIC_COUNT" -gt 0 ]; then
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_PROBLEMATIC_NAMES=$((TOTAL_PROBLEMATIC_NAMES + PROBLEMATIC_COUNT))
            if [ "$PROBLEMATIC_COUNT" -eq 1 ]; then
                echo "$SYS_NAME - 1 problematic name" >> /tmp/rom_names.menu
            else
                echo "$SYS_NAME - $PROBLEMATIC_COUNT problematic names" >> /tmp/rom_names.menu
            fi
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Problematic ROM names: $PROBLEMATIC_COUNT" >> "$OUTPUT_FILE"
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            mkdir -p "$SYS_PATH/.cache" 2>/dev/null
            if mv "$TEMP_FILE" "$SYS_PATH/.cache/problematic_names.txt" 2>/dev/null; then
                echo "Saved problematic names list to $SYS_PATH/.cache/problematic_names.txt" >> "$LOGS_PATH/Rom Inspector.txt"
            else
                echo "Warning: Failed to save problematic names list" >> "$LOGS_PATH/Rom Inspector.txt"
                rm -f "$TEMP_FILE"
            fi
        else
            rm -f "$TEMP_FILE"
            echo "No problematic ROM names found for $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
        fi
    done

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with problematic ROM names found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No problematic ROM names found." >> "$OUTPUT_FILE"
        show_message "No problematic ROM names found." 5
        return 0
    fi

    echo "Systems with problematic ROM names: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total problematic ROM names: $TOTAL_PROBLEMATIC_NAMES" >> "$LOGS_PATH/Rom Inspector.txt"

    if [ ! -s /tmp/rom_names.menu ]; then
        echo "Error: /tmp/rom_names.menu is empty or does not exist" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to generate systems menu." 5
        return 1
    fi

    while true; do
        rm -f /tmp/minui-output 2>/dev/null
        minui-list --disable-auto-sleep \
            --item-key rom_names \
            --file /tmp/rom_names.menu \
            --format text \
            --cancel-text "BACK" \
            --title "Systems with Problematic ROM Names" \
            --write-location /tmp/minui-output \
            --write-value state
        MINUI_EXIT_CODE=$?

        if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
            echo "User cancelled systems menu (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi
        if [ ! -f /tmp/minui-output ]; then
            echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Failed to read menu output." 5
            break
        fi

        idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
        if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
            echo "Invalid or no selection: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
            break
        fi

        selected_line=$(sed -n "$((idx + 1))p" /tmp/rom_names.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        PROBLEMATIC_NAMES_FILE="$SYS_PATH/.cache/problematic_names.txt"

        if [ ! -f "$PROBLEMATIC_NAMES_FILE" ] || [ ! -s "$PROBLEMATIC_NAMES_FILE" ]; then
            echo "Error: Problematic names list not found or empty for $selected_sys: $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No problematic ROM names found for $selected_sys." 5
            # Remove the system from the menu if the file is empty or missing
            sed -i "/^$selected_sys - /d" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
            echo "Removed $selected_sys from rom_names.menu due to empty/missing problematic names file" >> "$LOGS_PATH/Rom Inspector.txt"
            if [ ! -s /tmp/rom_names.menu ]; then
                echo "No systems with problematic ROM names remain" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "No systems with problematic ROM names remain." 5
                break
            fi
            continue
        fi

        while true; do
            rm -f /tmp/minui-output 2>/dev/null
            minui-list --disable-auto-sleep \
                --item-key problematic_name_items \
                --file "$PROBLEMATIC_NAMES_FILE" \
                --format text \
                --cancel-text "BACK" \
                --title "Problematic ROM Names for $selected_sys" \
                --write-location /tmp/minui-output \
                --write-value state
            MINUI_EXIT_CODE=$?

            if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled problematic names menu for $selected_sys (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
            if [ ! -f /tmp/minui-output ]; then
                echo "Error: minui-list output file /tmp/minui-output not found for problematic names" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to read menu output." 5
                break
            fi

            file_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$file_idx" = "null" ] || [ -z "$file_idx" ] || [ "$file_idx" = "-1" ]; then
                echo "Invalid or no selection for problematic name: idx=$file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            selected_file=$(sed -n "$((file_idx + 1))p" "$PROBLEMATIC_NAMES_FILE" 2>/dev/null)
            if [ -z "$selected_file" ]; then
                echo "Error: No file selected or invalid index: $file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Invalid file selection." 5
                break
            fi

            ROM_TO_RENAME="$SYS_PATH/$selected_file"
            echo "Selected ROM for renaming/deletion: $ROM_TO_RENAME" >> "$LOGS_PATH/Rom Inspector.txt"

            # Create a menu for rename or delete options
            > /tmp/rom_action.menu
            echo "Automatic rename ROM" >> /tmp/rom_action.menu
            echo "Delete ROM" >> /tmp/rom_action.menu
            echo "Skip" >> /tmp/rom_action.menu

            minui-list --disable-auto-sleep \
                --item-key rom_action \
                --file /tmp/rom_action.menu \
                --format text \
                --cancel-text "CANCEL" \
                --title "Action for $selected_file" \
                --write-location /tmp/minui-output \
                --write-value state
            ACTION_EXIT_CODE=$?

            if [ "$ACTION_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled action menu for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Action cancelled for $selected_file" 3
                continue
            fi

            action_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            action=$(sed -n "$((action_idx + 1))p" /tmp/rom_action.menu 2>/dev/null)

            case "$action" in
                "Automatic rename ROM")
                    # Suggest a cleaned-up name (keep spaces, only replace special chars with _)
                    SUGGESTED_NAME=$(echo "$selected_file" | sed -E 's/[][#$%*+?=|<>@;{}"]/_/g; s/_+/_/g; s/^_+|_+$//g; s/_/ /g; s/  +/ /g')
                    echo "Suggested name for $selected_file: $SUGGESTED_NAME" >> "$LOGS_PATH/Rom Inspector.txt"

                    # Create a confirmation menu
                    > /tmp/rename_confirm.menu
                    echo "Yes" >> /tmp/rename_confirm.menu
                    echo "No" >> /tmp/rename_confirm.menu

                    minui-list --disable-auto-sleep \
                        --item-key rename_confirm \
                        --file /tmp/rename_confirm.menu \
                        --format text \
                        --cancel-text "CANCEL" \
                        --title "Rename $selected_file to $SUGGESTED_NAME?" \
                        --write-location /tmp/minui-output \
                        --write-value state
                    CONFIRM_EXIT_CODE=$?

                    if [ "$CONFIRM_EXIT_CODE" -ne 0 ]; then
                        echo "User cancelled rename confirmation for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Rename cancelled for $selected_file" 3
                        continue
                    fi

                    confirm_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
                    if [ "$confirm_idx" = "0" ]; then
                        NEW_ROM_PATH="$SYS_PATH/$SUGGESTED_NAME"
                        if mv "$ROM_TO_RENAME" "$NEW_ROM_PATH" 2>/dev/null; then
                            echo "Renamed ROM: $ROM_TO_RENAME to $NEW_ROM_PATH" >> "$LOGS_PATH/Rom Inspector.txt"
                            echo "System: $selected_sys" >> "$OUTPUT_FILE"
                            echo "- Renamed: $selected_file to $SUGGESTED_NAME" >> "$OUTPUT_FILE"
                            show_message "Renamed: $selected_file to $SUGGESTED_NAME" 3
                            
                            # Log the content of PROBLEMATIC_NAMES_FILE before update
                            echo "DEBUG: Content of $PROBLEMATIC_NAMES_FILE before update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            cat "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: File is empty or not found" >> "$LOGS_PATH/Rom Inspector.txt"
                            # Log hex dump to detect invisible characters
                            echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE:" >> "$LOGS_PATH/Rom Inspector.txt"
                            xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                            
                            # Check write permissions for the .cache directory
                            CACHE_DIR="$SYS_PATH/.cache"
                            if [ ! -w "$CACHE_DIR" ]; then
                                echo "Error: No write permission for $CACHE_DIR" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "Error: No write permission for $CACHE_DIR" 5
                                continue
                            fi

                            # Check if PROBLEMATIC_NAMES_FILE is readable and not empty
                            if [ ! -r "$PROBLEMATIC_NAMES_FILE" ] || [ ! -s "$PROBLEMATIC_NAMES_FILE" ]; then
                                echo "Warning: $PROBLEMATIC_NAMES_FILE is not readable or empty, removing it" >> "$LOGS_PATH/Rom Inspector.txt"
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                            else
                                # Clean PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters
                                echo "DEBUG: Cleaning $PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters" >> "$LOGS_PATH/Rom Inspector.txt"
                                grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.clean" 2>>"$LOGS_PATH/Rom Inspector.txt" && mv "${PROBLEMATIC_NAMES_FILE}.clean" "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                # Remove the renamed file from the list
                                echo "DEBUG: Executing grep -vFx \"$selected_file\" \"$PROBLEMATIC_NAMES_FILE\" > \"${PROBLEMATIC_NAMES_FILE}.tmp\"" >> "$LOGS_PATH/Rom Inspector.txt"
                                if grep -vFx "$selected_file" "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.tmp" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                    if mv "${PROBLEMATIC_NAMES_FILE}.tmp" "$PROBLEMATIC_NAMES_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                        echo "Successfully updated $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                    else
                                        echo "Warning: Failed to move ${PROBLEMATIC_NAMES_FILE}.tmp to $PROBLEMATIC_NAMES_FILE, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                        rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                        rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    fi
                                else
                                    echo "Warning: Failed to execute grep -vFx for $selected_file in $PROBLEMATIC_NAMES_FILE, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                    rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                    rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                fi
                            fi
                            
                            # Log the content of PROBLEMATIC_NAMES_FILE after update
                            echo "DEBUG: Content of $PROBLEMATIC_NAMES_FILE after update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            cat "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: File is empty or not found" >> "$LOGS_PATH/Rom Inspector.txt"
                            # Log hex dump after update
                            echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE after update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                            
                            # Check if the file is empty or contains only whitespace
                            if [ ! -f "$PROBLEMATIC_NAMES_FILE" ] || [ ! -s "$PROBLEMATIC_NAMES_FILE" ] || ! grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" >/dev/null 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                echo "Problematic names file is empty or contains only whitespace for $selected_sys, removed" >> "$LOGS_PATH/Rom Inspector.txt"
                            fi
                            
                            # Update the count in the main menu
                            if [ -f "$PROBLEMATIC_NAMES_FILE" ]; then
                                NEW_COUNT=$(grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" | wc -l 2>>"$LOGS_PATH/Rom Inspector.txt" || echo 0)
                            else
                                NEW_COUNT=0
                            fi
                            echo "DEBUG: NEW_COUNT after rename for $selected_sys: $NEW_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
                            TOTAL_PROBLEMATIC_NAMES=$((TOTAL_PROBLEMATIC_NAMES - 1))
                            if [ "$NEW_COUNT" -eq 0 ]; then
                                sed -i "/^$selected_sys - /d" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "No more problematic names for $selected_sys, removed from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "All problematic names fixed for $selected_sys" 3
                                # Check if no systems with problematic names remain
                                if [ ! -s /tmp/rom_names.menu ]; then
                                    echo "No systems with problematic ROM names remain" >> "$LOGS_PATH/Rom Inspector.txt"
                                    show_message "No systems with problematic ROM names remain." 5
                                    break 2
                                fi
                                break
                            else
                                if [ "$NEW_COUNT" -eq 1 ]; then
                                    sed -i "/^$selected_sys - /c\\$selected_sys - 1 problematic name" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                    echo "Updated $selected_sys in rom_names.menu with 1 problematic name" >> "$LOGS_PATH/Rom Inspector.txt"
                                else
                                    sed -i "/^$selected_sys - /c\\$selected_sys - $NEW_COUNT problematic names" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                    echo "Updated $selected_sys in rom_names.menu with $NEW_COUNT problematic names" >> "$LOGS_PATH/Rom Inspector.txt"
                                fi
                            fi
                        else
                            echo "Error: Failed to rename $ROM_TO_RENAME to $NEW_ROM_PATH" >> "$LOGS_PATH/Rom Inspector.txt"
                            show_message "Error: Failed to rename $selected_file." 5
                            # Remove the file from the list anyway to prevent re-selection
                            if [ -w "$SYS_PATH/.cache" ]; then
                                if [ -r "$PROBLEMATIC_NAMES_FILE" ] && [ -s "$PROBLEMATIC_NAMES_FILE" ]; then
                                    echo "DEBUG: Executing grep -vFx \"$selected_file\" \"$PROBLEMATIC_NAMES_FILE\" > \"${PROBLEMATIC_NAMES_FILE}.tmp\" after failed rename" >> "$LOGS_PATH/Rom Inspector.txt"
                                    echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE before update (failed rename):" >> "$LOGS_PATH/Rom Inspector.txt"
                                    xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                                    # Clean PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters
                                    echo "DEBUG: Cleaning $PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters (failed rename)" >> "$LOGS_PATH/Rom Inspector.txt"
                                    grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.clean" 2>>"$LOGS_PATH/Rom Inspector.txt" && mv "${PROBLEMATIC_NAMES_FILE}.clean" "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    if grep -vFx "$selected_file" "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.tmp" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                        if mv "${PROBLEMATIC_NAMES_FILE}.tmp" "$PROBLEMATIC_NAMES_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                            echo "Successfully updated $PROBLEMATIC_NAMES_FILE after failed rename" >> "$LOGS_PATH/Rom Inspector.txt"
                                        else
                                            echo "Warning: Failed to move ${PROBLEMATIC_NAMES_FILE}.tmp to $PROBLEMATIC_NAMES_FILE after failed rename, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                            rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                            rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                        fi
                                    else
                                        echo "Warning: Failed to execute grep -vFx for $selected_file in $PROBLEMATIC_NAMES_FILE after failed rename, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                        rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                        rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    fi
                                else
                                    echo "Warning: $PROBLEMATIC_NAMES_FILE is not readable or empty after failed rename, removing it" >> "$LOGS_PATH/Rom Inspector.txt"
                                    rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                fi
                            else
                                echo "Error: No write permission for $SYS_PATH/.cache after failed rename" >> "$LOGS_PATH/Rom Inspector.txt"
                            fi
                            # Recalculate NEW_COUNT after failed rename
                            if [ -f "$PROBLEMATIC_NAMES_FILE" ]; then
                                NEW_COUNT=$(grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" | wc -l 2>>"$LOGS_PATH/Rom Inspector.txt" || echo 0)
                            else
                                NEW_COUNT=0
                            fi
                            echo "DEBUG: NEW_COUNT after failed rename for $selected_sys: $NEW_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
                            if [ "$NEW_COUNT" -eq 0 ]; then
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                sed -i "/^$selected_sys - /d" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "No more problematic names for $selected_sys, removed from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "All problematic names fixed for $selected_sys" 3
                                if [ ! -s /tmp/rom_names.menu ]; then
                                    echo "No systems with problematic ROM names remain" >> "$LOGS_PATH/Rom Inspector.txt"
                                    show_message "No systems with problematic ROM names remain." 5
                                    break 2
                                fi
                                break
                            fi
                        fi
                    else
                        echo "Rename cancelled for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Rename cancelled for $selected_file" 3
                    fi
                    ;;
                "Delete ROM")
                    if confirm_deletion "$ROM_TO_RENAME" "ROM"; then
                        if rm -f "$ROM_TO_RENAME" 2>/dev/null; then
                            echo "Deleted ROM: $ROM_TO_RENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                            echo "System: $selected_sys" >> "$OUTPUT_FILE"
                            echo "- Deleted: $selected_file" >> "$OUTPUT_FILE"
                            show_message "Deleted: $selected_file" 3
                            
                            # Log the content of PROBLEMATIC_NAMES_FILE before update
                            echo "DEBUG: Content of $PROBLEMATIC_NAMES_FILE before update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            cat "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: File is empty or not found" >> "$LOGS_PATH/Rom Inspector.txt"
                            # Log hex dump to detect invisible characters
                            echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE:" >> "$LOGS_PATH/Rom Inspector.txt"
                            xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                            
                            # Check write permissions for the .cache directory
                            CACHE_DIR="$SYS_PATH/.cache"
                            if [ ! -w "$CACHE_DIR" ]; then
                                echo "Error: No write permission for $CACHE_DIR" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "Error: No write permission for $CACHE_DIR" 5
                                continue
                            fi

                            # Check if PROBLEMATIC_NAMES_FILE is readable and not empty
                            if [ ! -r "$PROBLEMATIC_NAMES_FILE" ] || [ ! -s "$PROBLEMATIC_NAMES_FILE" ]; then
                                echo "Warning: $PROBLEMATIC_NAMES_FILE is not readable or empty, removing it" >> "$LOGS_PATH/Rom Inspector.txt"
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                            else
                                # Clean PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters
                                echo "DEBUG: Cleaning $PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters" >> "$LOGS_PATH/Rom Inspector.txt"
                                grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.clean" 2>>"$LOGS_PATH/Rom Inspector.txt" && mv "${PROBLEMATIC_NAMES_FILE}.clean" "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                # Remove the deleted file from the list
                                echo "DEBUG: Executing grep -vFx \"$selected_file\" \"$PROBLEMATIC_NAMES_FILE\" > \"${PROBLEMATIC_NAMES_FILE}.tmp\"" >> "$LOGS_PATH/Rom Inspector.txt"
                                if grep -vFx "$selected_file" "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.tmp" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                    if mv "${PROBLEMATIC_NAMES_FILE}.tmp" "$PROBLEMATIC_NAMES_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                        echo "Successfully updated $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                    else
                                        echo "Warning: Failed to move ${PROBLEMATIC_NAMES_FILE}.tmp to $PROBLEMATIC_NAMES_FILE, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                        rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                        rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    fi
                                else
                                    echo "Warning: Failed to execute grep -vFx for $selected_file in $PROBLEMATIC_NAMES_FILE, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                    rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                    rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                fi
                            fi
                            
                            # Log the content of PROBLEMATIC_NAMES_FILE after update
                            echo "DEBUG: Content of $PROBLEMATIC_NAMES_FILE after update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            cat "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: File is empty or not found" >> "$LOGS_PATH/Rom Inspector.txt"
                            # Log hex dump after update
                            echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE after update:" >> "$LOGS_PATH/Rom Inspector.txt"
                            xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                            
                            # Check if the file is empty or contains only whitespace
                            if [ ! -f "$PROBLEMATIC_NAMES_FILE" ] || [ ! -s "$PROBLEMATIC_NAMES_FILE" ] || ! grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" >/dev/null 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                echo "Problematic names file is empty or contains only whitespace for $selected_sys, removed" >> "$LOGS_PATH/Rom Inspector.txt"
                            fi
                            
                            # Update the count in the main menu
                            if [ -f "$PROBLEMATIC_NAMES_FILE" ]; then
                                NEW_COUNT=$(grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" | wc -l 2>>"$LOGS_PATH/Rom Inspector.txt" || echo 0)
                            else
                                NEW_COUNT=0
                            fi
                            echo "DEBUG: NEW_COUNT after delete for $selected_sys: $NEW_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
                            TOTAL_PROBLEMATIC_NAMES=$((TOTAL_PROBLEMATIC_NAMES - 1))
                            if [ "$NEW_COUNT" -eq 0 ]; then
                                sed -i "/^$selected_sys - /d" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "No more problematic names for $selected_sys, removed from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "All problematic names fixed for $selected_sys" 3
                                # Check if no systems with problematic names remain
                                if [ ! -s /tmp/rom_names.menu ]; then
                                    echo "No systems with problematic ROM names remain" >> "$LOGS_PATH/Rom Inspector.txt"
                                    show_message "No systems with problematic ROM names remain." 5
                                    break 2
                                fi
                                break
                            else
                                if [ "$NEW_COUNT" -eq 1 ]; then
                                    sed -i "/^$selected_sys - /c\\$selected_sys - 1 problematic name" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                    echo "Updated $selected_sys in rom_names.menu with 1 problematic name" >> "$LOGS_PATH/Rom Inspector.txt"
                                else
                                    sed -i "/^$selected_sys - /c\\$selected_sys - $NEW_COUNT problematic names" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                    echo "Updated $selected_sys in rom_names.menu with $NEW_COUNT problematic names" >> "$LOGS_PATH/Rom Inspector.txt"
                                fi
                            fi
                        else
                            echo "Error: Failed to delete $ROM_TO_RENAME" >> "$LOGS_PATH/Rom Inspector.txt"
                            show_message "Error: Failed to delete $selected_file." 5
                            # Remove the file from the list anyway to prevent re-selection
                            if [ -w "$SYS_PATH/.cache" ]; then
                                if [ -r "$PROBLEMATIC_NAMES_FILE" ] && [ -s "$PROBLEMATIC_NAMES_FILE" ]; then
                                    echo "DEBUG: Executing grep -vFx \"$selected_file\" \"$PROBLEMATIC_NAMES_FILE\" > \"${PROBLEMATIC_NAMES_FILE}.tmp\" after failed delete" >> "$LOGS_PATH/Rom Inspector.txt"
                                    echo "DEBUG: Hex dump of $PROBLEMATIC_NAMES_FILE before update (failed delete):" >> "$LOGS_PATH/Rom Inspector.txt"
                                    xxd "$PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "DEBUG: Unable to perform hex dump" >> "$LOGS_PATH/Rom Inspector.txt"
                                    # Clean PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters
                                    echo "DEBUG: Cleaning $PROBLEMATIC_NAMES_FILE to remove trailing newlines or invalid characters (failed delete)" >> "$LOGS_PATH/Rom Inspector.txt"
                                    grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.clean" 2>>"$LOGS_PATH/Rom Inspector.txt" && mv "${PROBLEMATIC_NAMES_FILE}.clean" "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    if grep -vFx "$selected_file" "$PROBLEMATIC_NAMES_FILE" > "${PROBLEMATIC_NAMES_FILE}.tmp" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                        if mv "${PROBLEMATIC_NAMES_FILE}.tmp" "$PROBLEMATIC_NAMES_FILE" 2>>"$LOGS_PATH/Rom Inspector.txt"; then
                                            echo "Successfully updated $PROBLEMATIC_NAMES_FILE after failed delete" >> "$LOGS_PATH/Rom Inspector.txt"
                                        else
                                            echo "Warning: Failed to move ${PROBLEMATIC_NAMES_FILE}.tmp to $PROBLEMATIC_NAMES_FILE after failed delete, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                            rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                            rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                        fi
                                    else
                                        echo "Warning: Failed to execute grep -vFx for $selected_file in $PROBLEMATIC_NAMES_FILE after failed delete, removing $PROBLEMATIC_NAMES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
                                        rm -f "${PROBLEMATIC_NAMES_FILE}.tmp" 2>/dev/null
                                        rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                    fi
                                else
                                    echo "Warning: $PROBLEMATIC_NAMES_FILE is not readable or empty after failed delete, removing it" >> "$LOGS_PATH/Rom Inspector.txt"
                                    rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                fi
                            else
                                echo "Error: No write permission for $SYS_PATH/.cache after failed delete" >> "$LOGS_PATH/Rom Inspector.txt"
                            fi
                            # Recalculate NEW_COUNT after failed delete
                            if [ -f "$PROBLEMATIC_NAMES_FILE" ]; then
                                NEW_COUNT=$(grep -v '^[[:space:]]*$' "$PROBLEMATIC_NAMES_FILE" | wc -l 2>>"$LOGS_PATH/Rom Inspector.txt" || echo 0)
                            else
                                NEW_COUNT=0
                            fi
                            echo "DEBUG: NEW_COUNT after failed delete for $selected_sys: $NEW_COUNT" >> "$LOGS_PATH/Rom Inspector.txt"
                            if [ "$NEW_COUNT" -eq 0 ]; then
                                rm -f "$PROBLEMATIC_NAMES_FILE" 2>/dev/null
                                sed -i "/^$selected_sys - /d" /tmp/rom_names.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                                echo "No more problematic names for $selected_sys, removed from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                                show_message "All problematic names fixed for $selected_sys" 3
                                if [ ! -s /tmp/rom_names.menu ]; then
                                    echo "No systems with problematic ROM names remain" >> "$LOGS_PATH/Rom Inspector.txt"
                                    show_message "No systems with problematic ROM names remain." 5
                                    break 2
                                fi
                                break
                            fi
                        fi
                    else
                        echo "Deletion cancelled for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                        show_message "Deletion cancelled for $selected_file" 3
                    fi
                    ;;
                "Skip")
                    echo "Skipped action for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Skipped: $selected_file" 3
                    ;;
                *)
                    echo "Error: Invalid action selected: $action" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Invalid action." 5
                    ;;
            esac
        done
    done

    echo "Exiting check_rom_names function" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "ROM names report saved to $OUTPUT_FILE" 5
    return 0
}

# Main menu
> /tmp/main_menu.menu || {
    echo "Error: Failed to create /tmp/main_menu.menu" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Error: Failed to create main menu." 5
    exit 1
}
echo "Check ROMs sizes" >> /tmp/main_menu.menu
echo "Remove duplicate ROMs" >> /tmp/main_menu.menu
echo "List missing covers" >> /tmp/main_menu.menu
echo "List orphaned files" >> /tmp/main_menu.menu
echo "Verify cover resolutions" >> /tmp/main_menu.menu
echo "Check ROMs names" >> /tmp/main_menu.menu
echo "Manage ZIP ROMs" >> /tmp/main_menu.menu
echo "Statistics" >> /tmp/main_menu.menu
echo "Exit" >> /tmp/main_menu.menu

while true; do
    minui-list --disable-auto-sleep \
        --item-key main_menu \
        --file /tmp/main_menu.menu \
        --format text \
        --cancel-text "EXIT" \
        --title "ROM Inspector" \
        --write-location /tmp/minui-output \
        --write-value state
    MINUI_EXIT_CODE=$?

    if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
        echo "User exited main menu (EXIT pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
        break
    fi
    if [ ! -f /tmp/minui-output ]; then
        echo "Error: minui-list output file /tmp/minui-output not found" >> "$LOGS_PATH/Rom Inspector.txt"
        show_message "Error: Failed to read menu output." 5
        break
    fi

    idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
    if [ "$idx" = "null" ] || [ -z "$idx" ] || [ "$idx" = "-1" ]; then
        echo "Invalid or no selection in main menu: idx=$idx" >> "$LOGS_PATH/Rom Inspector.txt"
        break
    fi

    selected_option=$(sed -n "$((idx + 1))p" /tmp/main_menu.menu 2>/dev/null)
    echo "Selected option: $selected_option" >> "$LOGS_PATH/Rom Inspector.txt"

    case "$selected_option" in
        "Check ROMs sizes")
            check_roms_sizes
            ;;
        "Remove duplicate ROMs")
            remove_duplicate_roms
            ;;
        "List missing covers")
            list_missing_covers
            ;;
        "List orphaned files")
            list_orphaned_files
            ;;
        "Verify cover resolutions")
            verify_cover_resolutions
            ;;
        "Check ROMs names")
            check_roms_names
            ;;
        "Manage ZIP ROMs")
            Manage_zip_roms
            ;;
        "Statistics")
            statistics
            ;;
        "Exit")
            echo "User selected Exit" >> "$LOGS_PATH/Rom Inspector.txt"
            break
            ;;
        *)
            echo "Error: Invalid selection in main menu: $selected_option" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "Error: Invalid selection." 5
            ;;
    esac
done

echo "Exiting ROM Inspector" >> "$LOGS_PATH/Rom Inspector.txt"
exit 0