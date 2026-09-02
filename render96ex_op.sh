#!/bin/bash
# =====================================================================
# Render96ex - PortMaster launcher - R36S OPTIMIZED EDITION v0.4
# Port folder: render96ex_op   (this script: render96ex_op.sh)
#
# Based on the original port by kotzebuedog.
#
# v0.4 - PUBLIC RELEASE (by José Pilas):
#   * 60 FPS is now the DEFAULT (sm64config.default.txt ships
#     "60fps true").  Tested on the R36S: full speed, normal game
#     logic, no extra speed-up.  You can switch between 30 and 60
#     fps at any time in the in-game menu (Options -> Graphics);
#     your choice is saved in conf/sm64config.txt and respected.
#   * NEW /logs folder with TWO log files:
#       logs/detailed.txt - HYPER detailed: every session is
#         appended with full system info (kernel, device model,
#         cpu, memory, storage, battery, temperature, firmware,
#         environment), the complete game + launcher output
#         (timestamped line by line), the active settings, the
#         music pack state, and full crash telemetry (exit code,
#         signal, fatal reason, kernel segfault/OOM evidence).
#       logs/simple.txt   - one line per session: date, result,
#         fps mode, music state, attempts, exit code, duration.
#     Both files rotate automatically when they grow too big.
#   * The old log.txt / crashlog.txt files are gone - everything
#     now lives in the /logs folder.
#
# v0.4.1 - GITHUB-FRIENDLY PACKAGING (by José Pilas):
#   * restool.zip (108 MB) now travels as 8 split 7z volumes in
#     parts/ (max 14 MB each) - no file in the port is anywhere
#     near the 100 MiB limit of git/GitHub, so the whole port
#     folder can be hosted as a plain git repository.
#
# v0.4.2 - THE COMMUNITY SPLIT VOLUMES (by José Pilas):
#   * The installer payload now ships DIRECTLY as 6 compressed
#     7z volumes in parts/ (restool.7z.001 ... 006, 16 MiB each,
#     ARM64-BCJ compressed by the community) - no zip wrapper:
#     the restool/ folder is extracted straight from the volumes,
#     which is faster (one extraction instead of extract + unzip)
#     and 13 MB smaller than the old zip-in-volumes approach.
#   * On the first start the launcher restores restool/ from
#     the volumes automatically: every volume is md5-checked
#     (parts/volumes.md5), 7-Zip verifies the CRC of every file
#     it extracts, the file count + total size are checked
#     against parts/manifest.txt and the executable bits are
#     re-applied from parts/exec.txt (7z volumes carry no unix
#     permissions).  All of it logged in logs/detailed.txt.
#   * A STATIC aarch64 7-Zip is bundled in tools/7zzs and is
#     preferred over any system 7z - the volumes use the ARM64
#     BCJ filter, which the old p7zip 16.02 of some firmwares
#     cannot decode.
#   * tools/install_mario64 restores the folder too when the
#     patcher is invoked directly, and skips the unzip step
#     when the folder already came from the volumes.
#   * parts/ can be deleted after a successful install to free
#     ~92 MB - see parts/README.txt.
#
# v4 history ("MUSIC + NORMAL SPEED + NO CRASH"), kept intact:
#   1. HQ MUSIC that actually plays - the DynOS audio engine loads
#      every track into RAM before the game starts; the 32 kHz
#      community pack needed ~243 MB and died on the 1 GB R36S.
#      The shipped pack is the same community-fixed music
#      (crash-free loop points by WD59-14) resampled to 22.05 kHz
#      stereo - the official PortMaster "lowmem" rate - ~157 MB in
#      RAM, stereo, nothing cut.
#   2. Deterministic game timing (vsync false, the engine paces
#      itself with its own timer; one or two swaps per tick
#      depending on the 60fps option - both run at normal speed
#      on the R36S).
#   3. No more invisible fatal errors: exit code 1 (the game's own
#      sys_fatal) is caught, the reason is printed to the log and
#      the right fallback is applied instead of failing silently.
#   Also: any ROM file name (.z64/.v64/.n64, copier header ok) in
#   original/, VERIFIED pack deploy, bounds-only audio verifier
#   before every start, crash guard with telemetry + auto-retry,
#   automatic migration from the old "render96ex" folder, memory
#   reclaim before every start.
# =====================================================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/$directory/ports/render96ex_op"
CONFDIR="$GAMEDIR/conf/"
RESTOOL_DIR="restool"
RESTOOL_ZIP="restool.zip"
RES_DIR="res"
BASEZIP="base.zip"
DEMOS_DIR="demos"
TEXTS_DIR="texts"
VERSION="us"  # at the moment only US is supported and has been tested in Portmaster
BASEROM="baserom.${VERSION}.z64"
SM64US_MD5="20b854b239203baf6c961b850a4a51a2"

# HQ music pack deployment (22.05 kHz stereo, community crash-free loop points)
AUDIO_SRC="$GAMEDIR/audiopack"
AUDIO_DST="$GAMEDIR/dynos/audio"
PACK_MARKER="$GAMEDIR/dynos/.r36s-pack-v4"
MIN_PACK_WAVS=200

mkdir -p "$CONFDIR"

cd $GAMEDIR

# ----------------------------------------------------------------------
# v0.4 LOG SYSTEM - /logs folder with detailed.txt + simple.txt
# ----------------------------------------------------------------------
LOGS_DIR="$GAMEDIR/logs"
DETAILED="$LOGS_DIR/detailed.txt"
SIMPLE="$LOGS_DIR/simple.txt"
mkdir -p "$LOGS_DIR"
touch "$DETAILED" "$SIMPLE" 2>/dev/null

# rotation: keep the files at a sane size on the SD card
if [ -s "$DETAILED" ] && [ "$(stat -c %s "$DETAILED" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  mv -f "$DETAILED" "$LOGS_DIR/detailed.old.txt" 2>/dev/null
fi
if [ -s "$SIMPLE" ] && [ "$(wc -l < "$SIMPLE" 2>/dev/null || echo 0)" -gt 500 ]; then
  tail -n 250 "$SIMPLE" > "${SIMPLE}.tmp" 2>/dev/null && mv -f "${SIMPLE}.tmp" "$SIMPLE"
fi

SESSION_EPOCH=$(date +%s)
SESSION_RESULT="startup"
ATTEMPT=0
GAME_RC=0
CRASHED=0
MUSIC_OFF=0
SUMMARY_WRITTEN=0

# one-line session summary in logs/simple.txt (runs on EVERY exit path)
finish_session() {
  [ "$SUMMARY_WRITTEN" -eq 1 ] && return 0
  SUMMARY_WRITTEN=1
  local dur dur_h dur_m dur_s fps music
  dur=$(( $(date +%s) - SESSION_EPOCH ))
  dur_h=$(( dur / 3600 )); dur_m=$(( (dur / 60) % 60 )); dur_s=$(( dur % 60 ))
  fps="?"
  if [ -f "${CONFDIR}sm64config.txt" ]; then
    fps=$(awk '/^60fps/ { print ($NF == "true") ? "60" : "30" }' "${CONFDIR}sm64config.txt" 2>/dev/null)
    [ -n "$fps" ] || fps="?"
  fi
  if [ -f "${CONFDIR}ost_disabled" ]; then
    music="disabled"
  elif [ -d "${GAMEDIR}/dynos/audio" ]; then
    music="on"
  else
    music="orig"
  fi
  printf '[%s] v0.4.2 %-22s | fps:%s | music:%s | attempts:%d | rc:%d | %02d:%02d:%02d\n' \
    "$(date '+%F %T')" "${SESSION_RESULT:-unknown}" "$fps" "$music" "$ATTEMPT" "$GAME_RC" \
    "$dur_h" "$dur_m" "$dur_s" >> "$SIMPLE" 2>/dev/null
  echo "--- session summary appended to logs/simple.txt ---"
  return 0
}
trap finish_session EXIT

# capture EVERYTHING (launcher + game output) in logs/detailed.txt, with a
# per-line timestamp when awk supports strftime (gawk/busybox awk do), plain
# append otherwise.  Output still reaches the terminal for SSH/console runs.
if printf '' | awk 'BEGIN { exit (strftime("%Y") + 0 < 2000) }' 2>/dev/null; then
  exec > >(awk -v LOG="$DETAILED" '{ print strftime("[%Y-%m-%d %H:%M:%S]") " " $0 >> LOG; close(LOG); print; fflush() }') 2>&1
else
  exec > >(tee -a "$DETAILED") 2>&1
fi

echo "================ SESSION $(date '+%F %T') - Render96ex R36S Optimized v0.4.2 ================"

# ----------------------------------------------------------------------
# HYPER detailed session header: full system + environment snapshot
# ----------------------------------------------------------------------
echo "--- system info ---"
echo "kernel:   $(uname -a 2>/dev/null)"
echo "model:    $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')"
echo "hostname: $(hostname 2>/dev/null)"
echo "cpu:      $(grep -m1 -E 'Processor|model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')  ($(nproc 2>/dev/null || echo '?') cores)"
grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null | sed 's/^/    mem: /'
echo "storage:  $(df -h "$GAMEDIR" 2>/dev/null | tail -n 1 | awk '{ print $4 " free of " $2 " (" $5 " used) on " $1 }')"
for bat in /sys/class/power_supply/*; do
  [ -f "$bat/capacity" ] && echo "battery:  $(cat "$bat/capacity" 2>/dev/null)% ($(cat "$bat/status" 2>/dev/null)) [$(basename "$bat")]"
done
for tz in /sys/class/thermal/thermal_zone*; do
  [ -f "$tz/temp" ] && echo "thermal:  $(basename "$tz") = $(cat "$tz/temp" 2>/dev/null)"
done
echo "firmware: CFW_NAME=${CFW_NAME:-?}  DEVICE_ARCH=${DEVICE_ARCH:-?}  display=${DISPLAY_WIDTH:-?}x${DISPLAY_HEIGHT:-?}  sticks=${ANALOG_STICKS:-?}"
echo "port:     script=$0  gamedir=$GAMEDIR  controlfolder=$controlfolder"
echo "--- environment (selected) ---"
env 2>/dev/null | grep -E '^(CFW|DEVICE|DISPLAY|ANALOG|PORT|XDG|HOME|USER|LOGNAME|PATH|SHELL|TERM|LD_)=' | grep -v SDL_GAMECONTROLLERCONFIG | sort | sed 's/^/    /'

# ----------------------------------------------------------------------
# v0.4.2 SPLIT-VOLUME RESTORE (GitHub-friendly packaging)
#
# The restool/ installer folder ships as 6 compressed 7z volumes
# in parts/.  It is restored HERE - before anything else needs
# it - with volume md5 checks, per-file CRC (done by 7-Zip while
# extracting), file count + size verification and exec-bit
# restore; every step is logged (this runs after the log
# redirect above).
# The restore only runs when the game is NOT installed yet (the
# folder is only needed for the installation, and it is deleted
# again after a successful install - re-extracting it on every
# launch would waste ~2 minutes each time).
# Failure POLICY is applied further below, once show_msg() exists:
# fatal only when the game is not installed yet and the folder
# could not be restored; a warning when the game is installed.
# See tools/restore_parts.sh and parts/README.txt for the details.
# ----------------------------------------------------------------------
RESTORE_FAILED=0
PARTS_RESTORED=0
if [ -d "$GAMEDIR/parts" ]; then
  if [ -f "$GAMEDIR/$RES_DIR/$BASEZIP" ] && [ -d "$GAMEDIR/$RES_DIR/$DEMOS_DIR" ] && [ -d "$GAMEDIR/$RES_DIR/$TEXTS_DIR" ]; then
    echo "--- split volumes in parts/ not needed (game already installed) ---"
  else
    source "${GAMEDIR}/tools/restore_parts.sh"
    restore_split_parts
  fi
fi

echo "--- game files ---"
if [ -f "$GAMEDIR/sm64.us.f3dex2e.${DEVICE_ARCH}" ]; then
  echo "binary:   $(stat -c %s "$GAMEDIR/sm64.us.f3dex2e.${DEVICE_ARCH}" 2>/dev/null) bytes  md5=$(md5sum "$GAMEDIR/sm64.us.f3dex2e.${DEVICE_ARCH}" 2>/dev/null | cut -d' ' -f1)"
fi
echo "pack-src: audiopack      $(find "$AUDIO_SRC" -name '*.wav' 2>/dev/null | wc -l) wavs"
echo "pack-dst: dynos/audio    $(find "$AUDIO_DST" -name '*.wav' 2>/dev/null | wc -l) wavs  (marker: $([ -f "$PACK_MARKER" ] && echo present || echo missing))"
echo "music:    ost_disabled=$([ -f "${CONFDIR}ost_disabled" ] && echo YES || echo no)"
echo "models:   dynos/packs: $(ls "$GAMEDIR/dynos/packs" 2>/dev/null | tr '\n' ' ')"
ROM_LIST=$(ls "$GAMEDIR/original" 2>/dev/null | grep -iE '\.(z64|v64|n64)$' | tr '\n' ' ')
echo "rom-drop: original/ -> ${ROM_LIST:-(no rom yet)}"
if [ -d "$GAMEDIR/parts" ]; then
  echo "parts:    $(ls "$GAMEDIR/parts" 2>/dev/null | grep -c '7z\.') volumes in parts/  restool/: $([ -f "$GAMEDIR/$RESTOOL_DIR/.parts-restored" ] && echo "restored ($(find "$GAMEDIR/$RESTOOL_DIR" -type f 2>/dev/null | wc -l) files)" || { [ -d "$GAMEDIR/$RESTOOL_DIR" ] && echo "present (no marker)" || echo "MISSING"; })"
fi
if [ -f "$GAMEDIR/$RESTOOL_DIR/$BASEROM" ]; then
  echo "baserom:  $RESTOOL_DIR/$BASEROM  $(stat -c %s "$GAMEDIR/$RESTOOL_DIR/$BASEROM" 2>/dev/null) bytes  md5=$(md5sum "$GAMEDIR/$RESTOOL_DIR/$BASEROM" 2>/dev/null | cut -d' ' -f1)"
fi
if [ -f "$GAMEDIR/$RES_DIR/$BASEZIP" ]; then
  echo "ressources: built ($RES_DIR/$BASEZIP present)"
else
  echo "ressources: NOT built yet (first start will build them from the rom)"
fi
echo "--- active settings (conf/sm64config.txt) ---"
if [ -f "${CONFDIR}sm64config.txt" ]; then
  sed 's/^/    /' "${CONFDIR}sm64config.txt"
else
  echo "    (no user config yet - the 60fps-on default will be installed on first start)"
fi

# remember where THIS session starts in the detailed log, so crash
# analysis only greps the current session
LOG_START_OFFSET=$(stat -c %s "$DETAILED" 2>/dev/null || echo 0)

export LD_LIBRARY_PATH="${GAMEDIR}/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export PATH="${GAMEDIR}/bin.${DEVICE_ARCH}:${PATH}"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Patcher config
export PATCHER_FILE="$GAMEDIR/tools/install_mario64"
export PATCHER_GAME="$(basename "${0%.*}")" # This gets the current script filename without the extension
export PATCHER_TIME="about 10 minutes"

# execution flag
$ESUDO chmod a+x "$GAMEDIR/sm64.us.f3dex2e.aarch64"
$ESUDO chmod a+x "$GAMEDIR/bin.aarch64/text_viewer"
chmod a+x "$GAMEDIR/tools/verify_audio_pack" "$GAMEDIR/tools/find_sm64_rom" "$GAMEDIR/tools/install_mario64" "$GAMEDIR/tools/7zzs" 2>/dev/null

# -------------------- BEGIN FUNCTIONS ----------------------

show_msg() { # $1 title, $2 message (text_viewer when available)
  echo "----------------------------------------------------------------"
  echo "$1"
  echo "$2"
  echo "----------------------------------------------------------------"
  if command -v text_viewer >/dev/null 2>&1; then
    text_viewer -e -f 25 -w -t "$1" -m "$2"
  else
    sleep 10
  fi
}

mem_available_mb() { # echo MemAvailable in MB (best effort)
  local v
  v=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
  echo "${v:-?}"
}

# --------------------- END FUNCTIONS ---------------------

# ----------------------------------------------------------------------
# v0.4.2 restore failure policy: fatal ONLY when the game is not
# installed yet AND the installer folder could not be restored from
# the split volumes.  When the game is already installed the folder
# is only needed for (re)installs, so a warning is enough.
# ----------------------------------------------------------------------
if [ "${RESTORE_FAILED}" -eq 1 ]; then
  if [ ! -d "${GAMEDIR}/${RESTOOL_DIR}" ] && [ ! -f "${GAMEDIR}/${RESTOOL_ZIP}" ] && { [ ! -f "$GAMEDIR/$RES_DIR/$BASEZIP" ] || [ ! -d "$GAMEDIR/$RES_DIR/$DEMOS_DIR" ] || [ ! -d "$GAMEDIR/$RES_DIR/$TEXTS_DIR" ]; }; then
    SESSION_RESULT="restore-failed"
    show_msg "Installer files problem" "Oh, no! The installer folder restool/\ncould not be restored from the\nsplit volumes in parts/.\nThe exact reason is in\n\n  logs/detailed.txt\n\nThe game is not installed yet, so it\ncannot continue without these files.\n\nRe-download or re-copy the complete\nrender96ex_op folder (parts/ must\ncontain all 6 restool.7z.00x files)\nand start again.\n\nYou can also restore restool/ on a\nPC:  7z x parts/restool.7z.001\n(needs 7-Zip 21.02 or newer).\n\nPress SELECT to close this window."
    exit 1
  fi
  echo "!! split-volume restore FAILED - continuing anyway: the game is already"
  echo "   installed and restool/ is only needed for (re)installs."
fi

# ----------------------------------------------------------------------
# One-time cleanup of older optimized builds (v1-v3) and migration from
# the original "render96ex" port:
#  - saves + settings + rom      (copied)
#  - built ressources res/       (moved - skips the ~10 min rebuild)
#  - dynos model packs           (moved - keeps the Render96 models)
# ----------------------------------------------------------------------
OLDDIR="${GAMEDIR}/../render96ex"
if [ -d "${OLDDIR}" ] && [ ! -f "${CONFDIR}.migrated" ]; then
  echo "--- upgrading from the previous render96ex release ---"
  for f in sm64config.txt sm64_save_file.bin sm64_save_file_0.sav sm64_save_file_1.sav sm64_save_file_2.sav sm64_save_file_3.sav; do
    if [ -f "${OLDDIR}/conf/$f" ]; then
      echo "  importing ${f}"
      cp -p "${OLDDIR}/conf/$f" "${CONFDIR}$f"
    fi
  done
  if [ -d "${OLDDIR}/original" ]; then
    mkdir -p "${GAMEDIR}/original"
    find "${OLDDIR}/original" -maxdepth 1 -type f \( -iname '*.z64' -o -iname '*.n64' -o -iname '*.v64' \) -exec cp -n {} "${GAMEDIR}/original/" \; 2>/dev/null
    echo "  rom imported into original/"
  fi
  if [ ! -f "${GAMEDIR}/${RES_DIR}/${BASEZIP}" ] && [ -f "${OLDDIR}/${RES_DIR}/${BASEZIP}" ] && [ -d "${OLDDIR}/${RES_DIR}/${DEMOS_DIR}" ] && [ -d "${OLDDIR}/${RES_DIR}/${TEXTS_DIR}" ]; then
    mkdir -p "${GAMEDIR}/${RES_DIR}"
    mv "${OLDDIR}/${RES_DIR}/"* "${GAMEDIR}/${RES_DIR}/" 2>/dev/null
    echo "  ressources imported (no rebuild needed)"
  fi
  if [ -d "${OLDDIR}/dynos/packs" ] && [ -n "$(ls -A "${OLDDIR}/dynos/packs" 2>/dev/null)" ]; then
    mkdir -p "${GAMEDIR}/dynos/packs"
    mv "${OLDDIR}/dynos/packs/"* "${GAMEDIR}/dynos/packs/" 2>/dev/null
    echo "  model pack(s) imported"
  fi
  touch "${CONFDIR}.migrated"
fi

# leftovers from v3/v4 (disabled packs, old markers, one-time fix markers)
if [ -d "${GAMEDIR}/dynos/audio.crashed-disabled" ]; then
  echo "--- removing the v3 disabled-pack leftovers ---"
  rm -rf "${GAMEDIR}/dynos/audio.crashed-disabled"
fi
rm -f "${CONFDIR}ost_disabled" "${AUDIO_DST}/.r36s-pack-v3" "${CONFDIR}.v4-speedfix" 2>/dev/null

# Check if mandatory ressources are installed
if [ ! -f $GAMEDIR/$RES_DIR/$BASEZIP ] || [ ! -d $GAMEDIR/$RES_DIR/$DEMOS_DIR ] || [ ! -d $GAMEDIR/$RES_DIR/$TEXTS_DIR ]
then
  echo "Ressources are missing."
  SESSION_RESULT="ok-install"

  mkdir -p "${RESTOOL_DIR}" "${GAMEDIR}/original"

  echo "Looking for the rom (any name / .z64 .n64 .v64 in the original folder)"
  "$GAMEDIR/tools/find_sm64_rom" "${GAMEDIR}/${RESTOOL_DIR}/${BASEROM}" "${GAMEDIR}"
  ROM_RC=$?

  if [ ! $ROM_RC -eq 0 ]
  then
    SESSION_RESULT="no-rom"
    case $ROM_RC in
      1) show_msg "No rom found" "Oh, no! No Super Mario 64 rom was found.\n\nPut your SM64 USA rom in the folder\n\n  ${GAMEDIR}/original\n\nAny file name works. Accepted formats: .z64, .v64, .n64 (USA version, md5sum ${SM64US_MD5}).\n\nPress SELECT to close this window." ;;
      *) SESSION_RESULT="bad-rom"; show_msg "Incompatible rom" "Oh, no! The rom found in the original folder is not a compatible Super Mario 64 USA image.\n\nCheck logs/detailed.txt for details (wrong region or bad dump).\n\nPress SELECT to close this window." ;;
    esac
    exit 1
  fi

  echo "Okey dokey! The rom has been found. The installation of ressources will start"

  if [ -f "$controlfolder/utils/patcher.txt" ]; then

    source "$controlfolder/utils/patcher.txt"

    rm -rf "${RESTOOL_DIR}"

  else
      echo "This port requires the latest version of PortMaster."
      SESSION_RESULT="pm-old"
      text_viewer -e -f 25 -w -t "PortMaster needs to be updated" -m "This port requires the latest version of PortMaster. Please update PortMaster first.\n\nPress SELECT to close this window."
      exit 0
  fi

fi

# ----------------------------------------------------------------------
# HQ MUSIC PACK - verified deploy (the actual star-crash fix)
#
# 22.05 kHz stereo WAVs, community-fixed loop points (WD59-14).
# This is the exact "lowmem" rate the official port uses on 1 GB
# devices, so the pack fits the R36S RAM budget (~157 MB in RAM).
# The copy is VERIFIED: a half-copied pack (full SD card, cable
# pulled, ...) is detected, retried once and finally reported,
# because a broken music.txt means silent music with no error.
# ----------------------------------------------------------------------
deploy_pack() {
  rm -rf "${AUDIO_DST}"
  mkdir -p "${GAMEDIR}/dynos" "${AUDIO_DST}"
  cp -R "${AUDIO_SRC}/." "${AUDIO_DST}/"
  sync
  local n
  n=$(find "${AUDIO_DST}" -name '*.wav' 2>/dev/null | wc -l)
  if [ -f "${AUDIO_DST}/music.txt" ] && [ "$n" -ge "$MIN_PACK_WAVS" ]; then
    echo "    HQ music pack installed and verified ($n wavs, 22.05 kHz stereo)."
    return 0
  fi
  echo "    !! deploy verification failed ($n wavs found, need >= $MIN_PACK_WAVS)"
  return 1
}

if [ -f "${CONFDIR}ost_disabled" ]; then
  echo "--- note: the HQ music pack is disabled (persistent audio-device failure in a"
  echo "          earlier session). delete conf/ost_disabled to try again."
elif [ -d "${AUDIO_SRC}" ]; then
  if [ ! -f "${PACK_MARKER}" ] || [ ! -f "${AUDIO_DST}/music.txt" ]; then
    echo "--- installing the HQ music pack (22.05 kHz stereo, one-time copy of ~230 MB) ---"
    if ! deploy_pack; then
      echo "--- retrying the pack installation once ---"
      if deploy_pack; then
        touch "${PACK_MARKER}"
      else
        # remove the half-copied pack: a partial music.txt/wav set would
        # make the engine's loader die with a fatal error at startup
        rm -rf "${AUDIO_DST}"
        show_msg "Music pack problem" "The HQ music pack could not be\ncopied completely. Most likely the\nSD card is full.\n\nFree some space (~250 MB) and start\nthe port again - the pack is installed\nautomatically.\n\nThe game runs with the original audio\nuntil then.\n\nPress SELECT to close this window."
      fi
    else
      touch "${PACK_MARKER}"
    fi
  else
    echo "--- HQ music pack already installed (marker ok) ---"
  fi
else
  echo "!! audiopack folder missing - HQ music will not be available"
fi

# ----------------------------------------------------------------------
# Audio pack integrity check (bounds-only - never rescales anything):
# verifies every music/jingle loop point against the real WAV headers
# and clamps out-of-bounds values (SIGSEGV guard).  With the shipped
# pack this is a pure no-op check that only reads ~80 small headers.
# ----------------------------------------------------------------------
if [ -x "${GAMEDIR}/tools/verify_audio_pack" ] && [ -d "${AUDIO_DST}" ]; then
  echo "--- audio pack integrity check ---"
  "${GAMEDIR}/tools/verify_audio_pack" "${AUDIO_DST}"
fi

# ----------------------------------------------------------------------
# Default settings: ships 60 FPS ON (tested: normal speed on the R36S,
# exactly like the classic 30 fps mode).  A default config is installed
# ONLY when the user has none - your own settings are never touched.
# Switch any time in-game: Options -> Graphics -> 60 FPS.
# ----------------------------------------------------------------------
if [ ! -f $CONFDIR/sm64config.txt ]
then
  echo "--- installing default settings (60fps ON, vsync off) ---"
  cp sm64config.default.txt $CONFDIR/sm64config.txt
fi
echo "--- fps mode: $(awk '/^60fps/ { print ($NF == "true") ? "60 fps" : "30 fps" }' "$CONFDIR/sm64config.txt" 2>/dev/null) (change it in Options -> Graphics) ---"

$GPTOKEYB "sm64.us.f3dex2e.${DEVICE_ARCH}" &

pm_platform_helper "$GAMEDIR/sm64.us.f3dex2e.${DEVICE_ARCH}"

# 1:1 display hack
if [[ ${DISPLAY_WIDTH} -eq ${DISPLAY_HEIGHT} ]]; then
  grep "# patch for 1:1 display" "${GAMEDIR}/hacksdl.${ANALOG_STICKS}.conf" 2>&1 >/dev/null
  [[ $? -eq 0 ]] || cat "${GAMEDIR}/hacksdl.${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}.conf" >> "${GAMEDIR}/hacksdl.${ANALOG_STICKS}.conf"
fi

# 3:2 (RG34XXH) display config
if  [[ ${DISPLAY_WIDTH} == 720 && ${DISPLAY_HEIGHT} == 480 ]]; then
  sed -i 's/window_w 640/window_w 720/g' "$GAMEDIR/conf/sm64config.txt"
fi

# use hacksdl to create a virtual analog stick from the dpad
if [[ -f "${GAMEDIR}/hacksdl.${ANALOG_STICKS}.conf" ]]; then
  export LD_PRELOAD="hacksdl.so"
  export HACKSDL_VERBOSE=1
  export HACKSDL_CONFIG_FILE="${GAMEDIR}/hacksdl.${ANALOG_STICKS}.conf"
fi

# Trick to get alsa dmix enabled on R36S with ArkOS
# ~/.asoundrc is removed before and port is started
# and put back after the port exits.
# So we put it back
[[ "$CFW_NAME" = *"ArkOS"* ]] && cp "${GAMEDIR}/asoundrc" "${HOME}/.asoundrc"

# ----------------------------------------------------------------------
# Launch with the v0.4 crash guard and full telemetry:
#   - exit 0                       : normal quit
#   - exit 1  (game sys_fatal)     : the reason is in logs/detailed.txt
#                                    (audio device, wav format, ...)
#                                    music-device failures disable the
#                                    music pack for this session and
#                                    restart; anything else retries once
#   - exit >=128 (killed by signal): crash - retry, then disable the
#                                    music pack and restart so the
#                                    session is always playable
#   Every abnormal exit is logged in logs/detailed.txt with its exit
#   code, the fatal reason, the kernel OOM lines and the kernel
#   segfault lines (fault address + PC), and summarized in
#   logs/simple.txt.  A session is NEVER lost: the guard restarts the
#   game automatically.
# ----------------------------------------------------------------------
MAX_ATTEMPTS=3

echo "--- memory before launch: $(mem_available_mb) MB available ---"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$(( ATTEMPT + 1 ))

  # reclaim memory (best effort, helps on 1 GB devices)
  $ESUDO sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1

  echo "--- game start (attempt $ATTEMPT of $MAX_ATTEMPTS) ---"
  ./sm64.us.f3dex2e.${DEVICE_ARCH} --savepath ./conf/
  GAME_RC=$?

  if [ $GAME_RC -eq 0 ] || [ $GAME_RC -eq 130 ]; then
    echo "--- game exit (code $GAME_RC) after $(( $(date +%s) - SESSION_EPOCH ))s of session ---"
    break
  fi

  CRASHED=1
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!! CRASH DETECTED !!!!!!!!!!!!!!!!!!!!!!!"
  echo "!! game closed unexpectedly (exit code $GAME_RC, attempt $ATTEMPT)"
  echo "!! time of crash: $(date '+%F %T')   memory available: $(mem_available_mb) MB"

  # give the log writer a moment to flush the game's last words
  sleep 0.2 2>/dev/null

  if [ $GAME_RC -eq 1 ]; then
    # the game's own fatal error handler: the exact reason was printed
    # to the log just before it died - show it here too
    echo "   the game reported a fatal error:"
    tail -c +$(( LOG_START_OFFSET + 1 )) "$DETAILED" 2>/dev/null | grep -iE "DynOS_|sys_fatal|fatal|unable to load|could not open" | tail -n 4 | sed 's/^/     /'
  else
    case $GAME_RC in
      137) echo "   exit 137 = SIGKILL: most likely the kernel OOM-killer (not enough RAM)." ;;
      139) echo "   exit 139 = SIGSEGV: segmentation fault (see log above)." ;;
      134) echo "   exit 134 = SIGABRT: internal abort." ;;
      132) echo "   exit 132 = SIGILL: illegal instruction." ;;
      *)   echo "   exit code meaning: signal $(( GAME_RC - 128 ))." ;;
    esac
  fi

  # kernel evidence (segfault address + oom lines), when readable
  KERN=$($ESUDO dmesg 2>/dev/null | grep -iE "segfault|unhandled|out of memory|oom-kill|killed process" | grep -iE "sm64|oom|memory" | tail -n 5)
  if [ -n "$KERN" ]; then
    echo "   kernel evidence:"
    echo "$KERN" | sed 's/^/     /'
  fi
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

  # decide the fallback
  if [ $ATTEMPT -lt $MAX_ATTEMPTS ] && [ -d "${GAMEDIR}/dynos/audio" ]; then
    if [ $ATTEMPT -eq 1 ]; then
      echo "!! crash guard: retrying once (transient crash check)"
    else
      echo "!! crash guard: disabling the HQ music pack and restarting with the original audio"
      MUSIC_OFF=1
      touch "${CONFDIR}ost_disabled"
      mv "${GAMEDIR}/dynos/audio" "${GAMEDIR}/dynos/audio.crashed-disabled"
    fi
  else
    break
  fi
done

if [ $CRASHED -eq 1 ]; then
  if [ $GAME_RC -eq 0 ] || [ $GAME_RC -eq 130 ]; then
    # a retry recovered the session
    if [ $MUSIC_OFF -eq 1 ]; then
      SESSION_RESULT="recovered-music-off"
      show_msg "Stability guard" "Heads-up: the game closed unexpectedly,\nso the HQ music pack was disabled and the\ngame restarted with the original audio.\n\nTo try the fixed music again later,\ndelete the file\n\n  conf/ost_disabled\n\nin the render96ex_op folder.\n\nIf this keeps happening, please share\n\n  logs/detailed.txt and logs/simple.txt\n\nfrom the render96ex_op folder.\n\nPress SELECT to close this window."
    else
      SESSION_RESULT="recovered"
      show_msg "Stability guard" "Heads-up: the game closed unexpectedly\nonce but recovered on retry.\n\nIf this keeps happening, please share\n\n  logs/detailed.txt and logs/simple.txt\n\nfrom the render96ex_op folder.\n\nPress SELECT to close this window."
    fi
  else
    SESSION_RESULT="failed"
    show_msg "Stability guard" "The game keeps closing unexpectedly.\n\nPlease share the files\n\n  logs/detailed.txt and logs/simple.txt\n\nfrom the render96ex_op folder so the\ncrash can be analyzed, then try a full\nre-install of the port.\n\nPress SELECT to close this window."
  fi
else
  # no crash: first-install sessions keep their label, everything else is a plain OK
  [ "$SESSION_RESULT" = "ok-install" ] || SESSION_RESULT="ok"
fi

echo "--- memory after exit: $(mem_available_mb) MB available ---"

echo "--- session end: result=${SESSION_RESULT} ---"

# write the one-line summary (also runs via trap on early exits)
finish_session

# let the log writer flush the last lines before PortMaster cleanup
sync
sleep 1

pm_finish
