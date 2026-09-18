
---

## Telink layer (`docker-dev-embedded-telink`)

Telink TLSR8258 (TC32 architecture, BLE) target image.

`$CROSS_PREFIX` = `tc32-elf-`

**This image branches off `docker-dev-template` directly, NOT off
`docker-dev-embedded-base`** — the tc32 toolchain is a 32-bit binary blob
needing `lib32-glibc`, and that multilib weight is kept out of the shared base.
So the embedded layer above is **absent here**. Specifically **not installed**:
`clang`/`clangd`/`clang-tidy`/`clang-format`, `lld`, `llvm`, `cppcheck`,
`ccache`, `pyocd`, `svd-find` and the SVD store, `dtc`, `lcov`, `rsync`,
`python-pyelftools`, `hidapi`. Do not reach for them.

### The compiler is NOT in this image

The Telink SDK is EULA-restricted and not redistributable, so the image ships a
**mount point**, not a compiler:

```
-v ~/telink/Telink_825X_SDK:/opt/telink/sdk:ro
```

`PATH` already includes `/opt/telink/sdk/tools/tc32/bin`, where the SDK's
`tc32-elf-gcc` blob lives. With nothing mounted there, `tc32-elf-gcc` simply
does not resolve — that is expected, not a broken image. Run
`/telink-sdk-check` (or `dev-doctor`) to confirm the mount before diagnosing
build failures.

| Area | What is here |
|---|---|
| Cross compiler | **Mounted, not installed** — `/opt/telink/sdk/tools/tc32/bin/tc32-elf-*` |
| Multilib runtime | `lib32-glibc`, `lib32-gcc-libs` (what the 32-bit tc32 blob needs) |
| Build | `make`, `cmake`, `ninja`, `meson` |
| Debug / flash | `gdb`, `openocd`, `probe-rs`, `stlink`, `dfu-util` |
| SWS flashing | `$TLSR_TOOLS` = `/opt/telink/tlsr-tools` (pvvx/TLSRPGM). **Needs dedicated programmer hardware** — a TB-04-KIT or TLSR8269 running TLSRPGM firmware, wired PD3→RESET, PD4↔SWS, PB4→Power. A bare USB-serial adapter is not enough. Telink's own BDT is Windows-GUI only |
| Serial | `picocom`, `screen`, `minicom`, `socat`, `python-pyserial` |
| Host tests | `gtest`, `catch2`, `gcovr` |
| Task runner | `mcu` — same runner and task keys as the embedded layer |
| CMake helpers | `/opt/embedded/cmake/embedded-common.cmake`, `host-test.cmake` (verbatim copies owned by `docker-dev-embedded-base`; resync with that repo's `scripts/sync-shared-assets.sh`) |

### Known-wrong file: `/opt/embedded/profile.json`

The bundled default profile is a **verbatim copy of the WCH one** — it declares
`chip: CH32V003F4P6`, `core: rv32ec`, `probe: wlink`, `flashTool: wlink`, and
its own `_note` says it is copied by `/scaffold-mcu-project wch`. None of that
applies to a TLSR8258, and `wlink` is not even installed in this image. **Do
not use it as a starting point or treat its values as this image's defaults.**
Write a TLSR8258 profile from `mcu --schema` instead.

### Skills in this layer

| Skill | Reach for it when |
|---|---|
| `tlsr-otp-vs-flash` | Deciding between OTP and flash storage, or debugging OTP writes |
| `tlsr8258-ble-stack` | TLSR8258 BLE stack bring-up and structure |

Command: `/telink-sdk-check` — run it first in this container.

These are flat `~/.claude/skills/<name>.md` files and will **not** trigger on
their own — read the file directly when its topic comes up. See the maintenance
rule in the baseline layer.
