THE PARTS/ FOLDER - WHAT IS THIS?
---------------------------------
The installer payload (the restool/ folder with the asset build
pipeline, 157 MB / 3318 files) is shipped here as 6 compressed
7z volumes - restool.7z.001 ... restool.7z.006 (16 MiB each) -
so that no file of this port gets anywhere near the 100 MiB
limit of git/GitHub.

You do NOT need to touch this folder. On the first start the
port extracts the restool/ folder from these volumes
automatically (volume checksums, per-file CRC, file count and
size all verified - every step is logged in logs/detailed.txt)
and then proceeds with the normal installation. A static
7-Zip build for the handheld is bundled in tools/7zzs, so no
additional software is required on the device.

MANUAL RESTORE (on a PC, only if you ever need it)
--------------------------------------------------
Open a terminal in the render96ex_op folder and run:

    7z x parts/restool.7z.001

(any 7-Zip 21.02 or newer, https://www.7-zip.org - the volumes
use the ARM64 BCJ filter, older versions cannot read them)

This extracts the restool/ folder right here, ready to be used
by the installer. You can check the volumes first with:

    cd parts && md5sum -c volumes.md5 && cd ..

NOTE for manual restores: 7z volumes do not carry unix
executable permissions. The port fixes that automatically on
the device (parts/exec.txt). If you restore manually and then
run tools/install_mario64 yourself, the port still applies
them - no action needed.

AFTER A SUCCESSFUL INSTALL
--------------------------
You can delete the parts/ folder to free ~92 MB on the SD
card. Keep it if you prefer a local backup for reinstalls -
the port re-extracts restool/ from it automatically whenever
the game data (res/) is missing and has to be rebuilt.

FILES
-----
restool.7z.00x   the 6 split volumes
manifest.txt     what the volumes contain + expected counts
volumes.md5      md5 of every volume (md5sum -c compatible)
exec.txt         the 33 files that need the executable bit
README.txt       this file
