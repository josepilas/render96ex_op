#!/bin/bash
# =====================================================================
# tools/restore_parts.sh - v0.4.3 split-volume self-restore support
#
# This file is SOURCED (not executed) by render96ex_op.sh and by
# tools/install_mario64.  It provides two functions:
#
#   find_7z
#       Echo the path of a usable 7-Zip binary and return 0, or
#       return 1 when none is available.  Search order: the bundled
#       STATIC aarch64 build in tools/7zzs FIRST (official 7-Zip
#       26.02 - it is statically linked, needs no libraries and it
#       understands the ARM64 BCJ filter these volumes use, which
#       the old p7zip 16.02 shipped on some firmwares cannot),
#       then a system 7zz / 7z / 7za / 7zr.
#
#   restore_split_parts
#       Rebuild every target that ships as split 7z volumes in the
#       parts/ folder (GitHub-friendly packaging: no single file in
#       the port is bigger than 50 MB).  Each volume set
#       parts/<name>.7z.001, .002, ... extracts DIRECTLY to
#       <name>/ (a folder) or <name> (a file) - no zip wrapper.
#       For every set it:
#         1. skips the work when <name> is already complete
#            (fast path: marker file + file count, costs almost
#            nothing; a manually restored tree with the exact
#            expected file count is adopted - exec bits fixed,
#            marker written - without re-extracting);
#         2. checks the volume list (count + total size, read
#            from the archive header) - missing volumes are
#            caught BEFORE any extraction starts;
#         3. verifies the md5 of EVERY volume against
#            parts/volumes.md5 (md5sum -c compatible file);
#         4. extracts to a temporary folder next to the target
#            (same SD card => the final move is an instant
#            rename, no second copy);  7-Zip checks the per-file
#            CRC of every extracted file;
#         5. verifies the extracted file count and total size
#            against parts/manifest.txt;
#         6. re-applies the executable bits from parts/exec.txt
#            (7z volumes do not carry unix permissions);
#         7. moves the verified folder into place.
#       Sets for the caller (global variables):
#         PARTS_RESTORED=1   something was rebuilt
#         RESTORE_FAILED=1   a rebuild (or a manifest problem)
#                            failed - the caller decides policy
#       Returns non-zero when RESTORE_FAILED was set.
#
# Requires $GAMEDIR to point at the port folder.  Uses only bash,
# find, stat, md5sum, grep, awk and sed (all already used by the
# launcher).
# =====================================================================

# global state for the caller (initialized at SOURCE time so every
# invocation pattern is safe, even when the caller did not pre-set
# them; a caller's explicit values are preserved)
RESTORE_FAILED=${RESTORE_FAILED:-0}
PARTS_RESTORED=${PARTS_RESTORED:-0}

find_7z() {
    local c bundled
    # bundled first: guaranteed new enough for the ARM64 BCJ filter
    bundled="${GAMEDIR}/tools/7zzs"
    if [ -f "$bundled" ]; then
        # make sure the exec bit survived whatever copied it
        # (no-op on FAT/exFAT, where everything is executable)
        chmod a+x "$bundled" 2>/dev/null || ${ESUDO:-} chmod a+x "$bundled" 2>/dev/null
        if [ -x "$bundled" ]; then
            echo "$bundled"
            return 0
        fi
    fi
    for c in 7zz 7z 7za 7zr; do
        if command -v "$c" >/dev/null 2>&1; then
            command -v "$c"
            return 0
        fi
    done
    return 1
}

# count files in a tree (echoes the number)
count_files() {
    find "$1" -type f 2>/dev/null | wc -l
}

# echo the total size in bytes of a tree (du -sb, fallback to find)
tree_bytes() {
    local b
    b=$(du -sb "$1" 2>/dev/null | cut -f1)
    [ -n "$b" ] && echo "$b" || echo "$(find "$1" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')"
}

# re-apply the executable bits listed in parts/exec.txt to the
# extracted tree.  $1 = base directory that CONTAINS the extracted
# <name>/ tree (paths in exec.txt are relative to it, e.g.
# "restool/bin/make")
apply_exec_bits() {
    local base="$1" list="${GAMEDIR}/parts/exec.txt" n=0
    if [ ! -f "$list" ]; then
        echo "   (no parts/exec.txt - skipping the executable-bit fix)"
        return 0
    fi
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        case "$rel" in \#*) continue ;; esac
        if [ -f "${base}/${rel}" ]; then
            chmod a+x "${base}/${rel}" 2>/dev/null && n=$(( n + 1 ))
        else
            echo "   !! exec.txt entry missing after extraction: ${rel}"
        fi
    done < "$list"
    echo "   executable permissions restored on $n file(s) (from parts/exec.txt)"
}

restore_split_parts() {
    local parts_dir="${GAMEDIR}/parts"
    if [ ! -d "$parts_dir" ]; then
        # nothing to do (pre-0.4.1 layout, or the user removed the
        # parts after a successful install) - perfectly normal
        return 0
    fi
    echo "--- split-volume restore (parts/) - $(date '+%F %T') ---"

    local sets found=0
    sets=$(find "$parts_dir" -name '*.7z.001' 2>/dev/null | sort)
    if [ -z "$sets" ]; then
        echo "   parts/ present but contains no *.7z.001 volume sets - nothing to do"
        return 0
    fi

    local vol name rel manifest="$parts_dir/manifest.txt"
    for vol in $sets; do
        found=1
        rel="${vol#"$parts_dir"/}"          # e.g. restool.7z.001
        name="${rel%.7z.001}"               # e.g. restool

        # ---------- manifest entry ----------
        local type expfiles expbytes entry
        if [ -f "$manifest" ]; then
            entry=$(awk -v n="$name" '($1 !~ /^#/) && ($1 == n) { print $2, $3, $4; exit }' "$manifest" 2>/dev/null)
        fi
        if [ -z "$entry" ]; then
            echo "   !! no manifest entry for '$name' - leaving its volumes alone"
            echo "      (re-copy the complete render96ex_op folder)"
            RESTORE_FAILED=1
            continue
        fi
        type=$(echo "$entry" | cut -d' ' -f1)
        expfiles=$(echo "$entry" | cut -d' ' -f2)
        expbytes=$(echo "$entry" | cut -d' ' -f3)
        local target="${GAMEDIR}/${name}"

        # ---------- 1) fast path ----------
        if [ "$type" = "dir" ]; then
            local marker="${target}/.parts-restored" have
            if [ -f "$marker" ] && [ "$(count_files "$target")" -ge "$expfiles" ]; then
                echo "   $name/: already restored and complete ($(count_files "$target") files) - nothing to do"
                continue
            fi
            # adopt a manually restored tree (exact count, no marker)
            have=$(count_files "$target" 2>/dev/null)
            if [ "$have" = "$expfiles" ] && [ -f "${target}/bin/make" ]; then
                echo "   $name/: complete tree found (restored manually?) - adopting it"
                apply_exec_bits "$GAMEDIR"
                touch "$marker" 2>/dev/null
                PARTS_RESTORED=1
                continue
            fi
        else
            if [ -f "$target" ] && [ "$(stat -c %s "$target" 2>/dev/null)" = "$expbytes" ]; then
                echo "   $name: already present and complete ($expbytes bytes) - nothing to do"
                continue
            fi
        fi

        # ---------- 2) needs a rebuild ----------
        echo "   $name: missing or incomplete - restoring it from the split volumes"
        local z
        if ! z=$(find_7z); then
            echo "   !! no 7-Zip found: no bundled tools/7zzs and no system"
            echo "      7z/7za/7zr/7zz.  Cannot restore $name."
            echo "      On a PC you can extract it manually:  7z x parts/${name}.7z.001"
            RESTORE_FAILED=1
            continue
        fi
        echo "   using 7-Zip: $z"

        # ---------- 3) volume presence + md5 (no 7z needed) ----------
        # parts/volumes.md5 lists every volume of the set with its
        # md5 (md5sum -c compatible), so missing and damaged volumes
        # are caught BEFORE 7-Zip is even started (a split archive
        # cannot even be listed when a volume is gone - the 7z
        # header lives in the LAST volume).
        local vlist md5f md5exp md5got bad=0 missing="" nv=0
        vlist=$(awk -v n="$name" '($2 !~ /^#/) && (index($2, n ".7z.") == 1) {print $2}' \
                "$parts_dir/volumes.md5" 2>/dev/null | sort)
        if [ -z "$vlist" ]; then
            echo "   !! parts/volumes.md5 has no entries for the ${name}.7z.00x"
            echo "      volumes - re-copy the complete render96ex_op folder."
            RESTORE_FAILED=1
            continue
        fi
        for md5f in $vlist; do
            nv=$(( nv + 1 ))
            volf="$parts_dir/$md5f"
            if [ ! -f "$volf" ]; then
                missing="$missing $md5f"
                continue
            fi
            md5exp=$(awk -v f="$md5f" '$2 == f {print $1; exit}' "$parts_dir/volumes.md5" 2>/dev/null)
            md5got=$(md5sum "$volf" 2>/dev/null | cut -d' ' -f1)
            if [ "$md5got" != "$md5exp" ]; then
                echo "   !! $md5f: md5 mismatch (got ${md5got:-none}, expected $md5exp)"
                bad=$(( bad + 1 ))
            fi
        done
        if [ -n "$missing" ]; then
            echo "   !! MISSING volume(s):$missing - cannot restore $name."
            echo "      Re-copy the complete parts/ folder (all $nv ${name}.7z.00x files)."
            RESTORE_FAILED=1
            continue
        fi
        if [ "$bad" -gt 0 ]; then
            echo "   !! $bad damaged volume(s) - $name was NOT restored."
            echo "      Re-download / re-copy the parts/ folder so every ${name}.7z.00x"
            echo "      file is complete."
            RESTORE_FAILED=1
            continue
        fi
        echo "   all $nv volume checksums OK"

        # ---------- 4) archive header sanity (needs every volume) ----------
        # v0.4.3: the awk below deliberately has NO "exit" - an early-exiting
        # awk closes the pipe while echo is still writing the ~3000-line 7z
        # listing into it, which printed "echo: write error: Broken pipe"
        # (twice) during the first-boot extraction.  The value is collected
        # in a variable and printed in END instead: same result, no noise.
        local listout nvol totsize
        listout=$("$z" l "$vol" 2>/dev/null) || listout=""
        nvol=$(printf '%s\n' "$listout" | awk -F'= ' '/^Volumes =/ {v=$2} END {print v}' | tr -d ' \r')
        totsize=$(printf '%s\n' "$listout" | awk -F'= ' '/^Total Physical Size =/ {v=$2} END {print v}' | tr -d ' \r')
        if [ -z "$nvol" ]; then
            # not a split archive: a single 7z file
            nvol=1
            totsize=$(printf '%s\n' "$listout" | awk -F'= ' '/^Physical Size =/ {v=$2} END {print v}' | tr -d ' \r')
        fi
        if [ -z "$totsize" ]; then
            echo "   !! could not read the volume set header of ${rel} - the set is"
            echo "      damaged.  Re-copy the complete parts/ folder."
            RESTORE_FAILED=1
            continue
        fi
        echo "   volume set: $nvol volumes, $totsize bytes total"

        # ---------- 5) extract ----------
        local tmp="${GAMEDIR}/.restore_tmp"
        rm -rf "$tmp"
        mkdir -p "$tmp"
        if ! "$z" x -y -bd -o"$tmp" "$vol" >/dev/null 2>"${tmp}/.7zerr"; then
            echo "   !! extraction FAILED. $name was NOT restored."
            if grep -qiE "filter|codec|method" "${tmp}/.7zerr" 2>/dev/null; then
                echo "      this 7-Zip is too old for these volumes (ARM64 BCJ filter)."
                echo "      Re-copy tools/7zzs from the package or install 7-Zip 21.02+."
            else
                echo "      The 7-Zip error was:"
                sed 's/^/      > /' "${tmp}/.7zerr" 2>/dev/null | head -n 5
            fi
            rm -rf "$tmp"
            RESTORE_FAILED=1
            continue
        fi

        local got="$tmp/$name"
        if [ "$type" = "dir" ] && [ ! -d "$got" ]; then
            echo "   !! extraction did not produce the '$name/' folder - archive layout"
            echo "      problem.  Re-download the render96ex_op package."
            rm -rf "$tmp"
            RESTORE_FAILED=1
            continue
        fi
        if [ "$type" != "dir" ] && [ ! -f "$got" ]; then
            echo "   !! extraction did not produce '$name' - archive layout problem."
            rm -rf "$tmp"
            RESTORE_FAILED=1
            continue
        fi

        # ---------- 6) verify count + size, restore exec bits ----------
        if [ "$type" = "dir" ]; then
            local gcount gbytes
            gcount=$(count_files "$got")
            gbytes=$(tree_bytes "$got")
            echo "   extracted: $gcount files, $gbytes bytes (expected: $expfiles files, $expbytes bytes)"
            if [ "$gcount" != "$expfiles" ] || [ "$gbytes" != "$expbytes" ]; then
                echo "   !! CHECKSUM MISMATCH (file count / size) - the volumes are damaged."
                echo "      Nothing was installed; re-download / re-copy the parts/ folder."
                rm -rf "$tmp"
                RESTORE_FAILED=1
                continue
            fi
            if [ ! -f "${got}/bin/make" ] || [ ! -f "${got}/main/extract_assets.py" ]; then
                echo "   !! extracted tree is missing key files (bin/make, main/extract_assets.py)."
                echo "      Nothing was installed; re-download the render96ex_op package."
                rm -rf "$tmp"
                RESTORE_FAILED=1
                continue
            fi
            apply_exec_bits "$tmp"
            touch "${got}/.parts-restored" 2>/dev/null
        else
            local gsize
            gsize=$(stat -c %s "$got" 2>/dev/null)
            echo "   extracted: $gsize bytes (expected: $expbytes bytes)"
            if [ "$gsize" != "$expbytes" ]; then
                echo "   !! CHECKSUM MISMATCH (size) - the volumes are damaged."
                rm -rf "$tmp"
                RESTORE_FAILED=1
                continue
            fi
        fi

        # ---------- 7) move into place (same filesystem => instant rename) ----------
        mkdir -p "$(dirname "$target")"
        if [ -e "$target" ]; then
            echo "   (the existing broken $name is kept as $name.corrupt.$(date +%s))"
            mv -f "$target" "${target}.corrupt.$(date +%s)" 2>/dev/null
        fi
        if mv "$got" "$target"; then
            echo "   $name: restored OK (count + size verified, exec bits in place)"
            PARTS_RESTORED=1
        else
            echo "   !! could not move $name into place (SD card full? permissions?)"
            RESTORE_FAILED=1
        fi
        rm -rf "$tmp"
    done

    if [ "${PARTS_RESTORED}" -eq 1 ]; then
        sync 2>/dev/null
    fi
    return ${RESTORE_FAILED}
}
