
# Render96ex — R36S Optimized Edition

<p align="center">
  <img src="https://i.ibb.co/jF1YfZm/Chat-GPT-Image-4-de-set-de-2026-13-37-49-clean-1.webp" alt="Render96ex — R36S Optimized Edition" width="100%">
</p>

**Version 0.4.2 — Public Release**
Maintained and released by **José Pilas**

Super Mario 64 with the Render96 treatment — enhanced 3D models, HD textures and
HQ music — running smoothly on 1 GB RAM handhelds like the **R36S** (RK3326),
through **PortMaster** (ArkOS / ROCKNIX / AmberELEC and friends).

This edition is a fixed and hardened repack of the official PortMaster port.
It is tuned specifically for the R36S: music that actually plays, 60 FPS by
default, verified deploys and hyper-detailed session logs — and it is
packaged so that **no single file is bigger than 50 MB**, so the whole port
can be hosted on GitHub or any git host without hitting the 100 MB
per-file limit.

---

## Features

* **HQ music that actually plays.** The DynOS audio engine loads every music
  track into RAM before the game starts. The stock pack is too heavy for a
  1 GB device and the old "fixes" either crashed the game or silently killed
  the music. This edition ships the community-fixed music (crash-free loop
  points by WD59-14) at 22.05 kHz **stereo** — the same "lowmem" rate the
  official installer uses on 1 GB devices — about 157 MB in RAM instead of
  243 MB. All tracks, all jingles, all character voices. Nothing cut.
* **60 FPS by default.** Tested on the R36S: full speed with normal game
  logic — no extra speed-up. You can switch between 30 and 60 FPS at any
  time in the in-game options menu (Options → Graphics → 60 FPS); your
  choice is saved and respected.
* **Any ROM file name.** Drop your Super Mario 64 **USA** rom in the
  `original/` folder — any file name, `.z64` / `.v64` / `.n64`, with or
  without a copier header. It is detected, converted and hash-verified
  automatically.
* **GitHub-friendly packaging.** No file in the port is bigger than
  50 MB: the 157 MB installer payload travels as 6 community-built
  compressed 7z volumes in `parts/` (16 MiB each) and is extracted and
  **fully verified automatically** on the first start — volume md5s,
  per-file CRC, file count and size, executable bits (a static 7-Zip
  for the handheld is bundled — nothing to install). See *The parts/
  folder* below.
* **Hyper-detailed logging.** A `logs/` folder with two files:
  * `logs/detailed.txt` — every session is appended with a full system
    snapshot (kernel, device model, CPU, memory, storage, battery,
    temperature, firmware), the complete launcher + game output timestamped
    line by line, the active settings, the music pack state and full crash
    telemetry (exit code, signal, fatal reason, kernel segfault/OOM
    evidence).
  * `logs/simple.txt` — one line per session: date, result, fps mode, music
    state, attempts, exit code, duration.
* **Self-healing launcher.** If the game is ever killed by a signal, it is
  retried automatically; if it keeps failing, the HQ music pack is disabled
  and the game restarts with the original audio so the session is always
  playable. Every abnormal exit is fully logged.
* **Verified deploys.** The music pack installation is checked (file count,
  `music.txt`, formats); a half-copied pack (full SD card, cable pulled) is
  detected, retried once and reported clearly.
* **Stereo audio everywhere** — a proper match for the R36S stereo speakers.
* **Automatic migration** from the older `render96ex` port and from earlier
  optimized builds: saves, settings, ROM, built resources and model packs
  are carried over.

---

## Requirements

* A handheld with an RK3326-class CPU and 1 GB RAM (R36S / RG35XX family and
  similar) running a PortMaster-compatible CFW (ArkOS, ROCKNIX, AmberELEC,
  TheRA, EmuELEC).
* **At least ~1.4 GB of free space** on the SD card for the port itself
  (the first launch temporarily needs up to 1.1 GB extra while the
  installer payload is restored from `parts/` and the assets are
  extracted from the rom).
* A legally owned **Super Mario 64 (USA)** rom.
  MD5: `20b854b239203baf6c961b850a4a51a2` · SHA1: `9bef1128717f958171a4afac3ed78ee2bb4e86ce`

---

## Installation

1. Copy the whole `render96ex_op` folder **and** the `render96ex_op.sh`
   script into your ports folder (e.g. `/roms/ports/` on ArkOS, or
   `/roms2/ports/` if your ports live on the second SD card).
2. Put your Super Mario 64 USA rom (any file name, `.z64` / `.v64` /
   `.n64`) into `render96ex_op/original/`.
3. Start the port from EmulationStation.

### First start

The first launch does some one-time work (~10 minutes):

* restores the `restool/` installer folder from the 6 split volumes
  in `parts/` (~1 minute, volume md5s + per-file CRC + file count and
  size + executable bits all verified);
* finds and verifies your rom, converts it to big-endian `.z64`;
* extracts and packages the game assets from the rom (this is the slow part);
* copies the HQ music pack into `dynos/audio` (~230 MB, verified).

Every start after that is fast: a quick audio pack integrity check, a memory
reclaim, then straight into the game.

### Upgrading from an earlier build

Just install this build next to the old one and start it once. Saves,
settings, your rom, the built resources and the Render96 model packs are
migrated automatically from the old `render96ex` folder; leftovers from
earlier optimized builds (disabled music packs, old markers) are cleaned
up automatically.

> Upgrading from v4? Your existing `conf/sm64config.txt` is kept as-is.
> v4 had forced 60 FPS off; if you never changed it, just flip it back in
> Options → Graphics → 60 FPS (or delete `conf/sm64config.txt` to get the
> new defaults).

---

## 60 FPS (and 30 FPS)

The game runs **60 FPS by default** in this edition — tested on the R36S at
full speed with normal game logic. The game logic itself always ticks at a
fixed rate; the 60 FPS mode simply renders twice per tick. If you prefer the
classic look (or want to save battery):

* press **Start → R1** in-game to open the options menu;
* **Options → Graphics → 60 FPS** toggles it;
* wait a few seconds for the framerate to stabilize.

Your choice is saved in `conf/sm64config.txt` and respected on every start.

> The optional Dynos 3D model pack can be choppy when combined with 60 FPS on
> some handhelds — see *Optional packages* below.

---

## Controls (R36S — 2 stick devices)

| Button | Action |
|--|--|
| D-pad | Movement (walk) |
| Left stick | Movement (run) |
| Right stick | Camera |
| L1 | Duck (Z) |
| R1 | Change camera mode (R) |
| L2 | Camera left |
| R2 | Camera right |
| A | Camera zoom out |
| X | Camera zoom in / make Mario run-walk slower |
| B | Jump |
| Y | Action (punch, dive, grab) |
| Start | Start / Pause |

* **Options menu:** press **Start → R1** during the game.
* **DynOS menu** (models, music, extras): press **Start → L2** during the game.

---

## The logs folder

Two files are written automatically inside `render96ex_op/logs/`:

* **`detailed.txt`** — the hyper-detailed log. Every session is appended with:
  * full system snapshot: kernel, device model, hostname, CPU, memory,
    storage, battery charge/state, temperatures, firmware (CFW name, arch,
    display, sticks), selected environment variables;
  * file inventory: game binary (size + MD5), music pack state (source and
    deployed wav counts, markers), model packs, rom info (size + MD5),
    resource build state;
  * your active settings (`conf/sm64config.txt` in full);
  * the split-archive restore trace: volumes found, which 7-Zip was
    used (system or the bundled static build), extracted vs expected
    size and MD5, and the result;
  * the complete launcher + game output, **timestamped line by line**;
  * crash telemetry: exit code, signal, the game's fatal reason (when it
    reports one), kernel segfault lines with fault address, OOM-killer
    evidence, memory available at crash time, and how the guard recovered.
  When it grows past ~1 MB it rotates to `detailed.old.txt`.
* **`simple.txt`** — one line per session, e.g.:
  `[2026-09-02 15:04:31] v0.4.2 ok | fps:60 | music:on | attempts:1 | rc:0 | 00:42:13`
  Possible results: `ok`, `ok-install` (first install), `recovered`
  (crashed once, retry fixed it), `recovered-music-off` (guard had to
  disable the music pack), `failed`, `no-rom`, `bad-rom`, `pm-old`,
  `restore-failed` (split volumes damaged/missing and the game not
  installed yet).

**Reporting a problem?** Attach both `logs/detailed.txt` and
`logs/simple.txt`.

---

## The parts/ folder (GitHub-friendly packaging)

No single file in this port is bigger than 50 MB, so the whole
`render96ex_op` folder can be pushed to GitHub (or any git host) without
hitting the 100 MB per-file limit. The one big thing the installer needs —
the `restool/` folder, 157 MB / 3318 files, the asset pipeline that builds
the game data from your rom — therefore travels as **6 compressed 7z
volumes** in `parts/` (`restool.7z.001` … `restool.7z.006`, 16 MiB each,
ARM64-BCJ compressed) that extract **directly** to the `restool/` folder —
no zip wrapper in between, which makes the first start faster and the
package smaller than the old approach.

* **You don't have to do anything.** On the first start the launcher
  restores `restool/` automatically: every volume is md5-checked against
  `parts/volumes.md5`, 7-Zip verifies the CRC of every file it extracts,
  the file count and total size are checked against `parts/manifest.txt`
  and the executable bits are re-applied from `parts/exec.txt` (7z volumes
  carry no unix permissions). Only then does the installation run, and
  every step is logged in `logs/detailed.txt`. `tools/install_mario64`
  performs the same restore too, so direct patcher runs are covered as
  well — and it skips the unzip step entirely when the folder already
  came from the volumes.
* A **static 7-Zip build for the handheld is bundled** as `tools/7zzs`
  (the official 7-Zip for Linux aarch64, statically linked — no
  libraries needed) and is **preferred over any system 7z**: these
  volumes use the ARM64 BCJ filter, which the old p7zip 16.02 shipped
  on some firmwares cannot decode.
* **Manual restore on a PC** (only if you ever need it) — open a
  terminal in the `render96ex_op` folder and run:

  ```
  7z x parts/restool.7z.001
  ```

  (any 7-Zip 21.02 or newer, <https://www.7-zip.org> — the volumes use
  the ARM64 BCJ filter, older versions cannot read them). This
  extracts the `restool/` folder right where the installer needs it.
  You can check the volumes first with `cd parts && md5sum -c
  volumes.md5`.
* **After a successful installation** you can delete the `parts/` folder
  to free ~92 MB on the SD card. Keep it if you prefer a local backup
  for reinstalls — the port re-extracts `restool/` from it automatically
  whenever the game data (`res/`) is missing and has to be rebuilt.

### Publishing this port on GitHub (for maintainers)

The repository root should contain exactly what the release archive
contains: `render96ex_op.sh` and the `render96ex_op/` folder (this
README lives inside the port folder — copy it to the repo root too if
you like). Every file is below 50 MB and the split volumes are 16 MiB
each, so a plain `git add -A && git push` works — no Git LFS
needed, and users can either clone the repo or download the GitHub zip;
the launcher restores `restool/` in both cases. If you ever replace
or update the `restool/` folder, re-split it the same way:

```
7z a -t7z -m0=LZMA2 -mf=ARM64 -v16m restool.7z restool
mv restool.7z.00* parts/
```

then re-generate `parts/volumes.md5` (`md5sum parts/restool.7z.00* >
parts/volumes.md5`), update the file count and byte count in
`parts/manifest.txt` and rebuild `parts/exec.txt` — the list of files
that need the executable bit (paths relative to the port folder, e.g.
`restool/bin/make`; take them from a zip-based reference copy with
`find restool -type f -perm -u+x > parts/exec.txt` run from the port
folder) — the launcher and `tools/install_mario64` pick the new set up
automatically from the manifest.

---

## The stability guard

If the game ever closes unexpectedly:

1. The exit code, the game's fatal reason (if any) and the kernel evidence
   (segfault address, OOM lines) are written to `logs/detailed.txt`.
2. The game is retried once (transient crashes happen).
3. If it fails again, the HQ music pack is disabled and the game restarts
   with the original audio — the session always stays playable.
4. A message explains what happened and how to re-enable the music later
   (delete `conf/ost_disabled`).

---

## Optional packages

The port ships three content packs (all included):

* **HD textures** (lowmem resize of the RENDER96-HD-TEXTURE-PACK) — active.
* **Dynos audio pack** (22.05 kHz, community-fixed loop points) — deployed
  and verified automatically.
* **Dynos 3D model pack** (Render96 Alpha 3.1, lowmem) — installed but
  **not enabled by default**: on most handhelds it is choppy when combined
  with 60 FPS. Enable it in the DynOS menu (**Start → L2**) if you want to
  try it.

---

## Reset configuration

* Game settings: delete/rename `conf/sm64config.txt` (defaults are
  reinstalled on next start — 60 FPS on, stereo).
* DynOS settings: delete/rename `conf/DynOS.1.1.alpha.config.txt`.

---

## Troubleshooting

* **"Installer files problem" / `restore-failed`** — the split volumes
  in `parts/` are damaged or incomplete (interrupted download/copy).
  The exact reason is in `logs/detailed.txt`. Re-copy the folder (all
  6 `restool.7z.00x` files) or restore `restool/` on a PC:
  `7z x parts/restool.7z.001` from the `render96ex_op` folder
  (needs 7-Zip 21.02 or newer).
* **No music after upgrading** — start the port once more: the pack is
  re-deployed and verified when the marker is missing.
* **"Music pack problem" message** — the SD card is full. Free ~250 MB and
  start again; the game runs with the original audio until then.
* **Game closes itself** — check `logs/detailed.txt`: the reason (with the
  kernel line) is in there. The guard restarts the game automatically; if
  it had to disable the music pack, delete `conf/ost_disabled` to give it
  another chance.
* **Speed feels wrong / choppy with 60 FPS** — toggle 60 FPS off in
  Options → Graphics and wait a few seconds.
* **Wrong rom** — only the **USA** version works (check the MD5 above).
  European/Japanese dumps and bad dumps are rejected with a message.

---

## Version history

* **v0.4.2 (2026-09-02)** — the community split volumes: the installer
  payload now ships **directly** as 6 ARM64-BCJ-compressed 7z volumes in
  `parts/` (`restool.7z.001`–`006`, 16 MiB each, ~9 MB smaller than
  before) — no zip wrapper, the `restool/` folder is extracted straight
  from the volumes, which is also faster (one extraction instead of
  extract + unzip).  Restore is verified four ways (volume md5s against
  the new `parts/volumes.md5`, 7-Zip per-file CRC, file count + byte
  count against `parts/manifest.txt`, executable bits from the new
  `parts/exec.txt` — 7z volumes carry no unix permissions, so the 33
  executables the build pipeline runs get their bits restored
  automatically; a manually restored tree is detected and adopted).
  The bundled `tools/7zzs` is now preferred over system 7z binaries
  (old p7zip 16.02 cannot decode the ARM64 filter); `tools/install_mario64`
  skips the unzip step when the folder came from the volumes; the
  restore only runs when the game is not installed yet (no more
  re-extraction on every launch after the post-install cleanup).
* **v0.4.1 (2026-09-02)** — GitHub-friendly packaging: `restool.zip`
  now ships as 8 split 7z volumes in `parts/` (max 14 MB each — no file
  anywhere near the 100 MiB git/GitHub limit), rebuilt and verified
  (size + MD5) automatically on the first start and by
  `tools/install_mario64` for direct patcher runs; static aarch64
  7-Zip bundled in `tools/7zzs`; new `restore-failed` session result;
  README publishing notes for maintainers.
* **v0.4 (2026-09-02)** — public release. 60 FPS by default (in-game
  toggle, choice respected); new `logs/` folder with `detailed.txt`
  (hyper-detailed, crash telemetry included) and `simple.txt` (session
  summaries), with automatic rotation; old `log.txt` / `crashlog.txt`
  replaced; this README.
* **v4** — the music + speed + crash fix: 22.05 kHz stereo community-fixed
  music pack (~157 MB in RAM), verified pack deploy, bounds-only audio
  loop verifier, fatal-error handling, crash guard with telemetry and
  auto-retry, automatic migration, memory reclaim. One-time 60 FPS → off
  migration (now retired — 60 FPS is back as the default).
* **v1–v3** — earlier optimized builds (32 kHz pack experiments, disabled
  packs, cleanup).

---

## Legal

You must own a legal copy of Super Mario 64. This package contains **no
Nintendo assets** — the game data is extracted from **your own rom** on
first launch. Don't ask PortMaster (or anyone else) how to obtain a rom.
License texts for the included community assets are in the `licenses/`
folder.

---

## Credits

* **José Pilas** — R36S Optimized Edition: concept, fixes, testing, release
  packaging and documentation (v0.4–v0.4.2).
* **Render96 team** — the Render96ex port itself, the enhanced models,
  textures and music direction. <https://linktr.ee/Render96> ·
  <https://github.com/Render96/Render96ex>
* **Retro Aesthetics team** — the huge work on the 3D models.
  <https://retroaesthetics.net/>
* **RENDER96-HD-TEXTURE-PACK** contributors (pokeheadroom and
  collaborators, with OldSchool HD / Render96; technical work by
  GhostlyDark) — the HD texture pack.
* **WD59-14** — the Render96ex music fix (crash-free loop points) that
  keeps the HQ music playing on low-memory devices.
* **kotzebuedog** — the original PortMaster packaging of Render96ex.
* **cdeletre** — Render96ex build work and the restool asset pipeline used
  by the port.
* **Igor Pavlov** — 7-Zip, whose statically-linked aarch64 build
  (bundled as `tools/7zzs`) makes the split-volume restore work on the
  handheld itself. <https://www.7-zip.org>
* **sm64ex / sm64pc community** — the sm64ex fork this port builds upon.
* **n64decomp** — the Super Mario 64 decompilation project, foundation of
  every SM64 PC port.
* **PortMaster** (PortsMaster team) — the handheld port manager and its
  community. <https://portmaster.games>
* **ArkOS** (BlackSeraph) and the other CFW maintainers — the firmware
  these ports run on.
* And every tester who reported a crash with a log attached — that is how
  this got fixed.

Super Mario 64 © Nintendo. This is a fan-made port package; it is not
affiliated with or endorsed by Nintendo.
