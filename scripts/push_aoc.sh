#!/bin/bash
# Copy add-on content (DLC) to an installed iPhone app's Documents/aoc, so a DLC bought after the app was built is used without building it again (main.m puts Documents/aoc
# before the DLC packed in the app; hle_fs.c aoc_dir). A game update is different: it changes the game's code, which is built into the app, so it needs a new build.
# Put the new DLC NSP in the game's folder and run scripts/build_ipa_from_nsp.py once: it extracts every DLC to <title ID>_build/aoc/<index>.img. Then:
# Usage: push_aoc.sh <device UDID> <bundle ID> <aoc folder | <index>.img ...>
#   a folder sends every <index>.img in it (a legacy <index>/ folder is packed into an image first, dm/tools/romfs_image.py); files send just those.
# The same files can be copied by hand with the Files app into the app's folder, as aoc/<index>.img. Run it while the app is installed; deleting the app deletes them.
set -eu
[ "$#" -ge 3 ] || { echo "usage: $0 <device UDID> <bundle ID> <aoc folder | <index>.img ...>" >&2; exit 1; }
dev=$1 id=$2; shift 2
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
imgs=()
for a in "$@"; do
    if [ -d "$a" ]; then
        for f in "$a"/*; do
            n=$(basename "$f")
            case "$n" in
                [1-9]*.img) [[ "${n%.img}" =~ ^[0-9]+$ ]] && imgs+=("$f");;
                [1-9]*) if [ -d "$f" ] && [[ "$n" =~ ^[0-9]+$ ]] && [ ! -f "$a/$n.img" ]; then
                            python3 -I "$here/../dm/tools/romfs_image.py" "$f" "$tmp/$n.img"; imgs+=("$tmp/$n.img"); fi;;
            esac
        done
    else
        n=$(basename "$a")
        [[ "$n" =~ ^[1-9][0-9]*\.img$ ]] || { echo "not an add-on content image (<index>.img): $a" >&2; exit 1; }
        imgs+=("$a")
    fi
done
[ "${#imgs[@]}" -gt 0 ] || { echo "no add-on content image (<index>.img) in: $*" >&2; exit 1; }
for img in "${imgs[@]}"; do
    python3 -I "$here/../dm/tools/romfs.py" "$img" ""   # a complete, valid RomFS image, as the host reads it
    xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier "$id" --source "$img" --destination "Documents/aoc/$(basename "$img")" -q
    echo "add-on content on the phone: $(basename "$img")"
done
echo "done: ${#imgs[@]} add-on content image(s) in $id's Documents/aoc; the game lists them at its next start"
