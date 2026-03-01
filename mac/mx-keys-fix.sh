#!/bin/bash
# Utilities — Linux desktop only
# Swaps TLDE/LSGT key definitions on Logitech MX Keys so F-row keys work
# without holding Fn. Modifies /usr/share/X11/xkb/symbols/de in place.
set -euo pipefail

file_path="/usr/share/X11/xkb/symbols/de"
temp_file="$file_path.temp"
patch_file="keyboard_layout.patch"

# Backup the original file
cp "$file_path" "$file_path.backup"

# Create a temporary modified copy of the original file
cp "$file_path" "$temp_file"

# Function to replace key definitions in the temporary file
replace_key_definitions() {
    local key=$1
    local original=$2
    local replacement=$3

    # Use sed to replace the original line with the replacement for the specific key
    sed -i "/key <$key>/c $replacement" "$temp_file"
}

# Replace TLDE and LSGT key definitions
replace_key_definitions "TLDE" "key <TLDE>  { [asciicircum,     degree,              notsign,     notsign ] };" "key <TLDE>  { [     less,     greater,                  bar, dead_belowmacron ] };"
replace_key_definitions "LSGT" "key <LSGT>  { [     less,     greater,                  bar, dead_belowmacron ] };" "key <LSGT>  { [asciicircum,     degree,              notsign,     notsign ] };"

# Generate the patch file by diffing the original and modified files
diff -u "$file_path" "$temp_file" > "$patch_file"

# Apply the patch
patch "$file_path" < "$patch_file"

# Cleanup: Remove the temporary file
rm "$temp_file"

echo "Patch applied successfully. Original file backed up at $file_path.backup"

