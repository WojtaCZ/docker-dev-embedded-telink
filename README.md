# docker-dev-embedded-telink

Telink TLSR8258 BLE development container. Targets the **TLSR8258** (TC32 architecture, 32-bit proprietary core, BLE 5.0).

Inherits directly from `docker-dev-template` (not `embedded-base`) because the tc32 toolchain is a 32-bit binary blob that requires `lib32-glibc`. This keeps that weight out of the shared ARM/RISC-V base image.

> Design rationale and verified issues: [`WRITEUP.md`](WRITEUP.md).

## Start here: `/telink-sdk-check`

Run it first in any session. The tc32 toolchain is not in the image — it lives
inside the host-mounted SDK — so almost every Telink failure traces back to
that mount. `dev-doctor` covers the same ground as part of a wider check.

## Prerequisites: Telink SDK (required, not in this image)

The tc32 toolchain is distributed **inside the Telink BLE SDK**, which is proprietary and not redistributable. You must download it separately:

1. Go to the Telink wiki or [Ai-Thinker-Open/Telink_825X_SDK](https://github.com/Ai-Thinker-Open/Telink_825X_SDK) for the open-source mirror.
2. Place the SDK at `~/telink/Telink_825X_SDK` (or set `DEV_TELINK_SDK` to its path).
3. `./scripts/dev-up.sh` mounts it read-only at `/opt/telink/sdk`, or set
   `DEV_TELINK_SDK=<path>`. The devcontainer mounts
   `~/telink/Telink_825X_SDK` by the same path.

If it is missing, `mcu build` says so explicitly rather than failing with a
confusing "tc32-elf-gcc: command not found".

After mounting, the tc32 toolchain is available:
```bash
tc32-elf-gcc --version
tc32-elf-g++ --version
```

## Quick start

```bash
# 1. Download and place the Telink SDK (see Prerequisites above)

# 2. Build and start the container
./scripts/dev-up.sh /path/to/your/ble_project

# 3. Verify toolchain is visible
which tc32-elf-gcc

# 4. Build an SDK sample
cd /opt/telink/sdk/b85m_ble_sdk/vendor/8258_ble_sample
make -j$(nproc) TC32_PATH=/opt/telink/sdk/tools/tc32
```

## Flashing — read this before planning work

Flashing a TLSR8258 needs Telink's **SWS** (Single Wire Serial) protocol. Be
clear-eyed that this leaf is weaker than `arm` and `wch` here:

**Option 1 — Telink BDT** (official). Windows GUI only. Cannot run in this
container; flash from the host.

**Option 2 — pvvx/TLSRPGM** (community, baked in at `$TLSR_TOOLS`). This is what
the profile's `flash`/`erase`/`reset` tasks drive:

```bash
mcu flash        # python3 $TLSR_TOOLS/TlsrPgm.py -p$PORT -b$PGM_BAUD -s -m we 0 build/firmware.bin
```

**It needs dedicated programmer hardware**, not just a USB-serial adapter: a
TB-04-KIT or a TLSR8269 module running the TLSRPGM firmware, wired
PD3→RESET, PD4↔SWS, PB4→Power. Confirm the flags against
`python3 $TLSR_TOOLS/TlsrPgm.py --help` and try it on a scratch board before
relying on it.

**Debugging:** there is no supported in-container GDB server for TC32. The
profile's `debugServer` task deliberately exits non-zero rather than printing a
message and reporting success. Plan on UART tracing, or debug from Windows with
BDT.

> Tasks that cannot work now **fail loudly**. Previously they were `echo`
> placeholders, so the VSCode Flash task appeared to succeed while doing
> nothing — worse than an error.

**Option 3: openocd** — not supported for TLSR8258/SWS natively.

## VSCode tasks

The shared task framework (`tasks.json`) is available via `/scaffold-mcu-project telink`. Task names are identical to other leaves (Build, Flash, Clean, etc.) but the Flash and Debug tasks are best-effort — point them at your chosen flashing tool in `.mcu-profile.json`.

## C++ notes

tc32-elf-g++ supports C++ classes and templates. The BLE SDK is written in C; wrap includes in `extern "C" { }`. No STL, no exceptions, no RTTI — the same rules as a tight bare-metal ARM project.

See the `tlsr8258-ble-stack` Claude skill for the SDK structure and the `tlsr-otp-vs-flash` skill for NVM usage.

## Template update propagation

This image tracks `ghcr.io/wojtacz/docker-dev-template:latest`. `dev-up.sh` passes `--pull` by default. CI rebuilds automatically via `repository_dispatch` (`template-image-updated` event) from `docker-dev-template`.


## Shared assets are copies

This leaf inherits from `docker-dev-template`, not from
`docker-dev-embedded-base`, because the tc32 toolchain is a 32-bit blob that
needs `lib32-glibc` and that multilib weight does not belong in the shared
embedded base.

The cost is that `udev-rules/`, `run-profile-task.sh`, `vscode-templates/`,
`profile.schema.json` and `cmake/` are **copies** of files owned by
`docker-dev-embedded-base`. Resync them from there:

```bash
../docker-dev-embedded-base/scripts/sync-shared-assets.sh --check .   # report drift
../docker-dev-embedded-base/scripts/sync-shared-assets.sh .           # resync
```

CI fails this repo's `asset-drift` job when they diverge, so the duplication
cannot rot silently.

## dev-doctor

```bash
dev-doctor           # table of every check
dev-doctor --json    # machine-readable; non-zero exit on any FAIL
```

Checks the 32-bit runtime, the SDK mount (a warning, not a failure — CI has no
SDK), whether `tc32-elf-gcc` actually executes, the community flashing tools,
and that the shared assets copied from `embedded-base` are present.
