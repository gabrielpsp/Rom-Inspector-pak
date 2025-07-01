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

# Reduced logging: Only log critical initialization details
echo "Initializing: USERDATA_PATH=$USERDATA_PATH, LOGS_PATH=$LOGS_PATH, PAK_DIR=$PAK_DIR, CACHE_FILE=$CACHE_FILE, EXPORT_FILE=$EXPORT_FILE, STATS_FILE=$STATS_FILE, ROM_SIZES_FILE=$ROM_SIZES_FILE, ORPHANED_FILES_FILE=$ORPHANED_FILES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"

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
    rm -f /tmp/stay_awake /tmp/platforms.menu /tmp/main_menu.menu /tmp/minui-output /tmp/roms_missing.menu /tmp/roms_missing_temp.menu /tmp/duplicates.menu /tmp/roms_duplicates.menu /tmp/rom_files.menu /tmp/rom_names.txt /tmp/rom_names_only.txt /tmp/statistics.menu /tmp/total_roms.menu /tmp/covers_percentage.menu /tmp/rom_sizes.menu /tmp/rom_sizes_temp.menu /tmp/roms_orphaned.menu /tmp/loading_pid 2>/dev/null
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
            echo "bin iso img zip"
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
            echo "zip"
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

check_rom_sizes() {
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

                    echo "$SYS_NAME - $ROM_COUNT ROM(s)" >> /tmp/total_roms.menu
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

                minui-list --disable-auto-sleep \
                    --item-key total_roms \
                    --file /tmp/total_roms.menu \
                    --format text \
                    --cancel-text "BACK" \
                    --title "Total ROMs per System" \
                    --write-location /tmp/minui-output \
                    --write-value state
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
        for ROM in "$SYS_PATH"/*; do
            [ -f "$ROM" ] && [ -r "$ROM" ] || continue
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
                ROM_SIZE=$((ROM_SIZE + SIZE))
                FILE_COUNT=$((FILE_COUNT + 1))
                if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
                    echo "Warning: Too many files in $SYS_NAME, limiting to $MAX_FILES" >> "$LOGS_PATH/Rom Inspector.txt"
                    break
                fi
            fi
        done

        # Skip systems with less than 1 MB of ROMs
        if [ "$ROM_SIZE" -lt "$MIN_ROM_SIZE" ]; then
            echo "Skipping $SYS_NAME: ROM size ($ROM_SIZE bytes) is less than 1 MB" >> "$LOGS_PATH/Rom Inspector.txt"
            continue
        fi

        # Calculate covers size
        MEDIA_PATH="$SYS_PATH/$image_folder"
        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            for COVER in "$MEDIA_PATH"/*.png; do
                [ -f "$COVER" ] && [ -r "$COVER" ] || continue
                SIZE=$(stat -c%s "$COVER" 2>/dev/null || echo 0)
                if [ "$SIZE" -eq 0 ]; then
                    echo "Warning: Failed to get size for $COVER" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                fi
                COVER_SIZE=$((COVER_SIZE + SIZE))
            done
        fi

        TOTAL_SYSTEM_SIZE=$((ROM_SIZE + COVER_SIZE))
        if [ "$TOTAL_SYSTEM_SIZE" -gt 0 ]; then
            ROM_SIZE_HUMAN=$(echo $ROM_SIZE | awk '{printf "%.1f%s", $1/1024/1024, "M"}')
            COVER_SIZE_HUMAN=$(echo $COVER_SIZE | awk '{printf "%.1f%s", $1/1024/1024, "M"}')
            TOTAL_SYSTEM_SIZE_HUMAN=$(echo $TOTAL_SYSTEM_SIZE | awk '{printf "%.1f%s", $1/1024/1024, "M"}')
            echo "$SYS_NAME - $TOTAL_SYSTEM_SIZE_HUMAN (ROMs: $ROM_SIZE_HUMAN, Covers: $COVER_SIZE_HUMAN)" >> /tmp/disk_usage.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_SIZE=$((TOTAL_SIZE + TOTAL_SYSTEM_SIZE))

            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "ROMs Size: $ROM_SIZE_HUMAN" >> "$OUTPUT_FILE"
            echo "Covers Size: $COVER_SIZE_HUMAN" >> "$OUTPUT_FILE"
            echo "Total Size: $TOTAL_SYSTEM_SIZE_HUMAN" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done

    TOTAL_SIZE_HUMAN=$(echo $TOTAL_SIZE | awk '{printf "%.1f%s", $1/1024/1024, "M"}')
    echo "Total Disk Usage: $TOTAL_SIZE_HUMAN" >> /tmp/disk_usage.menu
    echo "Total Disk Usage: $TOTAL_SIZE_HUMAN" >> "$OUTPUT_FILE"

    stop_loading

    if [ "$VALID_SYSTEMS_FOUND" -eq 0 ]; then
        echo "No systems with valid ROMs found." >> "$LOGS_PATH/Rom Inspector.txt"
        echo "No systems with valid ROMs found." >> "$OUTPUT_FILE"
        show_message "No valid systems found." 5
        return 1
    fi

    echo "Disk usage analysis completed. Systems found: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    cat /tmp/disk_usage.menu >> "$LOGS_PATH/Rom Inspector.txt" 2>/dev/null || echo "Error: Failed to read /tmp/disk_usage.menu" >> "$LOGS_PATH/Rom Inspector.txt"

    minui-list --disable-auto-sleep \
        --item-key disk_usage \
        --file /tmp/disk_usage.menu \
        --format text \
        --cancel-text "BACK" \
        --title "Disk Usage per System" \
        --write-location /tmp/minui-output \
        --write-value state

    show_message "Disk usage report saved to $OUTPUT_FILE" 5
    return 0
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
            echo "$SYS_NAME - $MISSING_COUNT missing cover(s)" >> /tmp/roms_missing.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_MISSING_COUNT=$((TOTAL_MISSING_COUNT + MISSING_COUNT))
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Missing covers: $MISSING_COUNT" >> "$OUTPUT_FILE"
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

        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            for COVER in "$MEDIA_PATH"/*.png; do
                [ -f "$COVER" ] && [ -r "$COVER" ] || continue
                COVER_BASENAME="${COVER##*/}"
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
            echo "$SYS_NAME - $ORPHANED_COUNT orphaned file(s)" >> /tmp/roms_orphaned.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_ORPHANED_COUNT=$((TOTAL_ORPHANED_COUNT + ORPHANED_COUNT))
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Orphaned files: $ORPHANED_COUNT" >> "$OUTPUT_FILE"
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            mv "$TEMP_FILE" "$SYS_PATH/.cache/orphaned_files.txt" 2>/dev/null || {
                echo "Warning: Failed to save orphaned files list to $SYS_PATH/.cache/orphaned_files.txt" >> "$LOGS_PATH/Rom Inspector.txt"
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

        selected_line=$(sed -n "$((idx + 1))p" /tmp/roms_orphaned.menu 2>/dev/null)
        selected_sys=$(echo "$selected_line" | sed -E 's/ - (.*)$//')

        SYS_PATH="/mnt/SDCARD/Roms/$selected_sys"
        ORPHANED_FILES_FILE="$SYS_PATH/.cache/orphaned_files.txt"

        if [ ! -f "$ORPHANED_FILES_FILE" ] || [ ! -s "$ORPHANED_FILES_FILE" ]; then
            echo "Error: Orphaned files list not found or empty for $selected_sys: $ORPHANED_FILES_FILE" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No orphaned files found for $selected_sys." 5
            continue
        fi

        show_message "Loading orphaned files for $selected_sys..." forever
        LOADING_PID=$!

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

            FILE_TO_DELETE="$SYS_PATH/$image_folder/$selected_file"
            echo "Attempting to delete: $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"

            if confirm_deletion "$FILE_TO_DELETE" "orphaned file"; then
                if rm -f "$FILE_TO_DELETE" 2>/dev/null; then
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
                        sed -i "/^$selected_sys - /c\\$selected_sys - $NEW_ORPHANED_COUNT orphaned file(s)" /tmp/roms_orphaned.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                    else
                        echo "No more orphaned files for $selected_sys, removing from menu" >> "$LOGS_PATH/Rom Inspector.txt"
                        sed -i "/^$selected_sys - /d" /tmp/roms_orphaned.menu 2>>"$LOGS_PATH/Rom Inspector.txt"
                        rm -f "$ORPHANED_FILES_FILE"
                        break
                    fi
                else
                    echo "Error: Failed to delete $FILE_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to delete $selected_file." 5
                fi
            else
                echo "Deletion cancelled for $selected_file" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Deletion cancelled for $selected_file" 3
            fi
        done

        stop_loading
        # If the menu is empty, exit the system selection loop
        if [ ! -s /tmp/roms_orphaned.menu ]; then
            echo "No systems with orphaned files remain" >> "$LOGS_PATH/Rom Inspector.txt"
            show_message "No systems with orphaned files remain." 5
            break
        fi
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

        echo "Verifying cover resolutions for system: $SYS_NAME" >> "$LOGS_PATH/Rom Inspector.txt"
        MEDIA_PATH="$SYS_PATH/$image_folder"
        PROBLEMATIC_COUNT=0
        TEMP_FILE=$(mktemp)
        FILE_COUNT=0

        if [ -d "$MEDIA_PATH" ] && [ -r "$MEDIA_PATH" ]; then
            for COVER in "$MEDIA_PATH"/*.png; do
                [ -f "$COVER" ] && [ -r "$COVER" ] || continue
                COVER_BASENAME="${COVER##*/}"
                RESOLUTION=$(identify -format "%w x %h" "$COVER" 2>/dev/null || echo "unknown")
                if [ "$RESOLUTION" = "unknown" ]; then
                    echo "Warning: Failed to get resolution for $COVER" >> "$LOGS_PATH/Rom Inspector.txt"
                    continue
                fi

                WIDTH=$(echo "$RESOLUTION" | cut -d' ' -f1)
                HEIGHT=$(echo "$RESOLUTION" | cut -d' ' -f3)
                EXPECTED_RESOLUTION="480x480"  # Example resolution, adjust as needed
                if [ "$RESOLUTION" != "$EXPECTED_RESOLUTION" ] || [ "$WIDTH" -lt 100 ] || [ "$HEIGHT" -lt 100 ]; then
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
            echo "$SYS_NAME - $PROBLEMATIC_COUNT problematic cover(s)" >> /tmp/cover_resolutions.menu
            VALID_SYSTEMS_FOUND=$((VALID_SYSTEMS_FOUND + 1))
            TOTAL_PROBLEMATIC_COVERS=$((TOTAL_PROBLEMATIC_COVERS + PROBLEMATIC_COUNT))
            echo "System: $SYS_NAME" >> "$OUTPUT_FILE"
            echo "Problematic covers: $PROBLEMATIC_COUNT" >> "$OUTPUT_FILE"
            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            mv "$TEMP_FILE" "$SYS_PATH/.cache/problematic_covers.txt" 2>/dev/null || {
                echo "Warning: Failed to save problematic covers list to $SYS_PATH/.cache/problematic_covers.txt" >> "$LOGS_PATH/Rom Inspector.txt"
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
        echo "No problematic cover resolutions found." >> "$OUTPUT_FILE"
        show_message "No problematic cover resolutions found." 5
        return 0
    fi

    echo "Systems with problematic covers: $VALID_SYSTEMS_FOUND" >> "$LOGS_PATH/Rom Inspector.txt"
    echo "Total problematic covers: $TOTAL_PROBLEMATIC_COVERS" >> "$LOGS_PATH/Rom Inspector.txt"
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

        show_message "Loading problematic covers for $selected_sys..." forever
        LOADING_PID=$!

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

            if [ "$MINUI_EXIT_CODE" -ne 0 ]; then
                echo "User cancelled problematic covers menu for $selected_sys (BACK pressed)" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi
            if [ ! -f /tmp/minui-output ]; then
                echo "Error: minui-list output file /tmp/minui-output not found for problematic covers" >> "$LOGS_PATH/Rom Inspector.txt"
                show_message "Error: Failed to read menu output." 5
                break
            fi

            file_idx=$(jq -r '.selected' /tmp/minui-output 2>/dev/null)
            if [ "$file_idx" = "null" ] || [ -z "$file_idx" ] || [ "$file_idx" = "-1" ]; then
                echo "Invalid or no selection for problematic cover: idx=$file_idx" >> "$LOGS_PATH/Rom Inspector.txt"
                break
            fi

            selected_file=$(sed -n "$((file_idx + 1))p" "$PROBLEMATIC_COVERS_FILE" 2>/dev/null)
            selected_cover=$(echo "$selected_file" | cut -d' ' -f1)
            COVER_TO_DELETE="$SYS_PATH/$image_folder/$selected_cover"

            if confirm_deletion "$COVER_TO_DELETE" "cover"; then
                if rm -f "$COVER_TO_DELETE" 2>/dev/null; then
                    echo "Deleted problematic cover: $COVER_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    echo "System: $selected_sys" >> "$OUTPUT_FILE"
                    echo "- Deleted: $selected_file" >> "$OUTPUT_FILE"
                    show_message "Deleted: $selected_cover" 3
                    grep -v "^$selected_file$" "$PROBLEMATIC_COVERS_FILE" > "${PROBLEMATIC_COVERS_FILE}.tmp" && mv "${PROBLEMATIC_COVERS_FILE}.tmp" "$PROBLEMATIC_COVERS_FILE"
                    if [ ! -s "$PROBLEMATIC_COVERS_FILE" ]; then
                        rm -f "$PROBLEMATIC_COVERS_FILE"
                        break
                    fi
                else
                    echo "Error: Failed to delete $COVER_TO_DELETE" >> "$LOGS_PATH/Rom Inspector.txt"
                    show_message "Error: Failed to delete $selected_cover." 5
                fi
            else
                show_message "Deletion cancelled for $selected_cover" 3
            fi
        done

        stop_loading
    done

    echo "Exiting verify_cover_resolutions function" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Cover resolutions report saved to $OUTPUT_FILE" 5
    return 0
}

# Main menu
> /tmp/main_menu.menu || {
    echo "Error: Failed to create /tmp/main_menu.menu" >> "$LOGS_PATH/Rom Inspector.txt"
    show_message "Error: Failed to create main menu." 5
    exit 1
}
echo "Check ROM sizes" >> /tmp/main_menu.menu
echo "Remove duplicate ROMs" >> /tmp/main_menu.menu
echo "List missing covers" >> /tmp/main_menu.menu
echo "List orphaned files" >> /tmp/main_menu.menu
echo "Verify cover resolutions" >> /tmp/main_menu.menu
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
        "Check ROM sizes")
            check_rom_sizes
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