#!/bin/bash
# Copy add-on content (DLC) to an installed iPhone app's Documents/aoc, so a DLC bought after the app was built is used without building it again (main.m puts Documents/aoc
# before the DLC packed in the app; hle_fs.c aoc_dir). A game update is different: it changes the game's code, which is built into the app, so it needs a new build.
# Put the new DLC NSP in the game's folder and run scripts/build_ipa_from_nsp.py once: it extracts every DLC to <title ID>_build/aoc/<index>.img. Then:
# Usage: push_aoc.sh <device UDID> <bundle ID> <aoc folder | <index>.img ...>
#   a folder sends every <index>.img in it (a legacy <index>/ folder is packed into an image first, dm/tools/romfs_image.py); files send just those.
# The same files can be copied by hand with the Files app into the app's folder, as aoc/<index>.img. Run it while the app is installed; deleting the app deletes them.
# The images named are added to Documents/aoc or replace the one of the same index; the other DLC there stay (push_romfs.sh with a resources.env replaces the whole set).
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
for img in "${imgs[@]}"; do python3 -I "$here/../dm/tools/romfs.py" "$img" ""; done   # each a complete, valid RomFS image, as the host reads it: before anything is copied
# The images go over AFC (house_arrest; libimobiledevice's afcclient), which streams them, as push_romfs.sh sends the game's image: devicectl's copy has the Mac's
# CoreDeviceService read the whole file into its own memory (docs/reference/packing.md), and a DLC can be as large as a game (Assassin's Creed: The Ezio Collection, 10.4 GB).
# AFC writes Documents/aoc/<index>.img.part, a name the host never takes (hle_misc.c aoc_load lists <index> and <index>.img; hle_fs.c aoc_dir opens those), and renames it
# once the device holds all of it: afcclient exits 0 even when a command fails, so the size on the device decides. ROMFS_PUSH_VIA=afc / devicectl chooses, as for
# push_romfs.sh (default: afc when afcclient is installed).
via=${ROMFS_PUSH_VIA:-auto}
if [ "$via" = auto ]; then if command -v afcclient > /dev/null; then via=afc; else via=devicectl; fi; fi
if [ "$via" = afc ]; then
    afc() { afcclient -u "$dev" --container "$id" -- "$@"; }
    remote_size() { afc info "$1" 2> /dev/null | sed -n 's/^ *"st_size": *\([0-9][0-9]*\).*/\1/p'; }
    remote_type() { afc info "$1" 2> /dev/null | sed -n 's/^ *"st_ifmt": *"\([A-Z_]*\)".*/\1/p'; }
    [ "$(remote_type /Documents)" = S_IFDIR ] || { echo "[RED] afcclient cannot open Documents of $id on device $dev: it needs the device's UDID (idevice_id -l lists the connected ones; devicectl's identifier and the device's name do not work), a USB connection, and the app installed. ROMFS_PUSH_VIA=devicectl copies through devicectl instead" >&2; exit 1; }
    kind=$(remote_type /Documents/aoc)
    if [ -z "$kind" ]; then afc mkdir /Documents/aoc; kind=$(remote_type /Documents/aoc); fi
    [ "$kind" = S_IFDIR ] || { echo "[RED] Documents/aoc of $id is not a folder on the device (${kind:-it could not be made}): nothing was copied" >&2; exit 1; }
elif [ "$via" = devicectl ]; then
    mem=$(sysctl -n hw.memsize)
    for img in "${imgs[@]}"; do
        size=$(stat -f %z "$img")
        if [ -z "${ROMFS_PUSH_VIA:-}" ] && [ "$size" -gt $((mem / 2)) ]; then
            echo "[RED] $(basename "$img") ($((size >> 20)) MB) is larger than half this Mac's memory ($((mem >> 20)) MB): devicectl copies it through memory and can fill the swap. Install afcclient (brew install libimobiledevice) and run this again, or set ROMFS_PUSH_VIA=devicectl to copy it anyway. Nothing was copied" >&2
            exit 1
        fi
    done
else echo "ROMFS_PUSH_VIA is afc or devicectl, not $via" >&2; exit 1; fi
for img in "${imgs[@]}"; do
    n=$(basename "$img"); size=$(stat -f %z "$img")
    if [ "$via" = afc ]; then
        afc put -f "$img" "/Documents/aoc/$n.part"
        got=$(remote_size "/Documents/aoc/$n.part")
        [ "$got" = "$size" ] || { echo "[RED] the copy of $n is incomplete: Documents/aoc/$n.part holds ${got:-nothing} of $size bytes (a full device, or the cable); the DLC on the phone is unchanged. Run this again" >&2; exit 1; }
        # A legacy folder of the same index would be listed beside the image and win nothing (aoc_dir takes the image first), but it holds the old DLC's space
        if [ "$(remote_type "/Documents/aoc/${n%.img}")" = S_IFDIR ]; then afc rm -rf "/Documents/aoc/${n%.img}" < /dev/null > /dev/null || true; fi
        afc rm "/Documents/aoc/$n" > /dev/null 2>&1 || true
        afc mv "/Documents/aoc/$n.part" "/Documents/aoc/$n"
        got=$(remote_size "/Documents/aoc/$n")
        [ "$got" = "$size" ] || { echo "[RED] Documents/aoc/$n.part was not renamed to $n ($n holds ${got:-nothing} of $size bytes). Run this again" >&2; exit 1; }
    else
        xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier "$id" --source "$img" --destination "Documents/aoc/$n" -q
    fi
    echo "add-on content on the phone: $n"
done
echo "done: ${#imgs[@]} add-on content image(s) in $id's Documents/aoc; the game lists them at its next start"
