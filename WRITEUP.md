# docker-dev-embedded-telink — Functional Writeup

> Leaf image for Telink TLSR8258 (TC32, BLE). Inherits **`docker-dev-template`
> directly** — it is the one leaf that bypasses `docker-dev-embedded-base`.
> Fleet-wide architecture: [`docker-dev-embedded-base/WRITEUP.md`](../docker-dev-embedded-base/WRITEUP.md)

> **Note:** the analysis below describes the repo *as it was audited* on
> 2026-09-02. Every defect listed has since been fixed and every proposal
> implemented — see **Status: implemented** at the end for the mapping. The
> analysis is kept because it records *why* the current design is the way it is.


## 1. Purpose and position

Development container for the **Telink TLSR8258** — a BLE 5.0 SoC built on
Telink's proprietary **TC32** 32-bit core (not ARM, not RISC-V).

```
docker-dev-template
  ├── docker-dev-embedded-base
  └── docker-dev-embedded-telink   ← THIS IMAGE (branches off the template)
```

### Why it bypasses `embedded-base`

The tc32 toolchain is a **32-bit binary blob** shipped inside Telink's SDK. It
needs `lib32-glibc` + `lib32-gcc-libs`, which requires enabling Arch's `multilib`
repository. Rather than push multilib weight into the shared base that ARM and
WCH also pull, this leaf enables multilib for itself.

The trade-off is duplication: `udev-rules/`, `run-profile-task.sh`, and
`vscode-templates/` are copied verbatim from `docker-dev-embedded-base`, and the
whole `paru-bin` AUR bootstrap is repeated. Three copies of the same files now
drift independently.

## 2. What this image implements

| Piece | Detail |
| --- | --- |
| Multilib enable | `sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf` — uncomments the multilib block, then `-Syu`. |
| 32-bit runtime | `lib32-glibc`, `lib32-gcc-libs` — required for the tc32 blob to execute. |
| Base-equivalent tooling | `make cmake ninja jq python usbutils picocom tio screen minicom openocd stlink gdb-multiarch` |
| AUR | `paru-bin`, then `blackmagic` + `probe-rs-bin` |
| SDK mount point | `/opt/telink` created and chowned to `dev`; SDK expected at `/opt/telink/sdk` |
| `PATH` | `/opt/telink/sdk/tools/tc32/bin` prepended |
| Duplicated from base | `udev-rules/`, `run-profile-task.sh`, `vscode-templates/` |
| Claude skills (2) | `tlsr8258-ble-stack`, `tlsr-otp-vs-flash` |

### The SDK-mount pattern

The Telink SDK is EULA-restricted and not redistributable, so the image ships
**no compiler at all** — it ships a *mount point* and a `PATH` entry. The user
supplies the SDK:

```bash
-v ~/telink/Telink_825X_SDK:/opt/telink/sdk
```

This is the correct pattern for licence-encumbered vendor toolchains, and it is
worth reusing elsewhere in the fleet — notably for STM32CubeCLT and STM32CubeWBA
in the ARM leaf (see [ARM writeup §4.5](../docker-dev-embedded-arm/WRITEUP.md)).

## 3. Verified defects

Checked against live Arch/AUR sources on 2026-09-02.

| # | Severity | Finding |
| --- | --- | --- |
| **L1** | **Blocker** | `gdb-multiarch` **is not an Arch package** (that is the Debian name). `pacman -S` aborts the whole transaction on an unknown target, so this image cannot build. Use **`gdb`** — Arch's `gdb` has been built with `--enable-targets=all --enable-multilib` since June 2024. |
| **L2** | **Blocker** | `tio` is **AUR-only**, not in `extra`. Same failure mode. Drop it (picocom/minicom/screen are already installed) or move it to the AUR stage. |
| **L3** | **Blocker** | The AUR step installs `blackmagic` and `probe-rs-bin`. **Neither package exists in AUR.** `probe-rs` is now in Arch `extra` (0.32.0) — use pacman. `blackmagic` has no AUR package and is not needed: BMP presents a GDB server directly on `/dev/ttyACM0`. |
| L4 | Medium | The `PATH` entry `/opt/telink/sdk/tools/tc32/bin` is set unconditionally. If the SDK is not mounted, `tc32-elf-gcc` is silently absent with no diagnostic. Add an entrypoint check that warns when `/opt/telink/sdk` is empty. |
| L5 | Medium | `profile.json`'s `flash`, `erase`, `reset`, and `debugServer` are all **`echo` placeholders** — no actual flashing is implemented. The README is honest about this (BDT is Windows-GUI-only; SWS via BMP is "experimental"), but the VSCode Flash task will appear to succeed while doing nothing. Make them exit non-zero instead of echoing. |
| L6 | Medium | `settings.json` — same non-existent `@modelcontextprotocol/server-fetch` npm package as the rest of the fleet. Use `uvx mcp-server-fetch`. |
| L7 | Low | `docker-dev-template`'s CI dispatches `event_type=template-image-updated` to this repo, but this repo's `publish.yml` listens for `repository_dispatch: types: [base-image-updated]`. **The event names do not match, so the fan-out silently never fires.** Align them. |
| L8 | Low | `run-profile-task.sh` and `vscode-templates/` are verbatim copies from `embedded-base` with no sync mechanism. |
| L9 | Low | The base's `launch.json` is copied here, but none of its three configurations (openocd/BMP Cortex-Debug, RISC-V GDB) applies to TC32. A TC32 debug config, or a note that debugging is unsupported, would be more honest. |

## 4. Proposed features

### 4.1 Fix the three blocking package names (L1–L3)

```dockerfile
        gdb \
        probe-rs \
        # drop: gdb-multiarch, tio, blackmagic, probe-rs-bin
```

With `probe-rs` from `extra` and `blackmagic` gone, the **entire `paru-bin`
bootstrap can be deleted from this image** — several minutes off every CI build.

### 4.2 SDK presence check at startup (fixes L4)

```bash
if [ ! -x /opt/telink/sdk/tools/tc32/bin/tc32-elf-gcc ]; then
    echo "WARN: Telink SDK not mounted at /opt/telink/sdk — tc32 toolchain unavailable." >&2
    echo "      Run with: -v ~/telink/Telink_825X_SDK:/opt/telink/sdk" >&2
fi
```

### 4.3 Real flashing via `tlsr_tools` (fixes L5)

Vendor the community `TLSR825x_Tools` SWS implementation into the image and wire
it into the profile, so `flash` actually flashes. Failing that, make the
placeholder commands `exit 1` with the reason — a task that reports success
without doing anything is worse than one that fails.

### 4.4 De-duplicate the shared assets (L8)

Extract `udev-rules/`, `run-profile-task.sh`, and `vscode-templates/` into a
tiny `docker-dev-embedded-common` image and pull them with
`COPY --from=ghcr.io/wojtacz/docker-dev-embedded-common:latest /opt/embedded /opt/embedded`.
That gives Telink the shared assets without inheriting multilib-incompatible
tooling — the best of both branches.

### 4.5 Fix the CI dispatch event name (L7)

Either change `docker-dev-template` to send `base-image-updated`, or add
`template-image-updated` to this repo's `repository_dispatch` types list. Right
now this image never auto-rebuilds.

---

## Status: implemented 2026-09-02

Everything proposed in section 4 is now in the repo, and every defect in
section 3 is fixed.

| Item | Resolution |
| --- | --- |
| L1 — `gdb-multiarch` does not exist on Arch | `gdb` (built `--enable-targets=all`) |
| L2 — `tio` is AUR-only | dropped; `picocom`/`minicom`/`screen`/`socat` cover it |
| L3 — `blackmagic` and `probe-rs-bin` are not in AUR | `probe-rs` from `extra`; `blackmagic` dropped (BMP needs no host package). **The `paru-bin` bootstrap is gone entirely.** |
| L4 — silent missing SDK | `/telink-sdk-check` command, a `dev-doctor` check, and build tasks that name the real problem |
| L5 — `echo` placeholders reporting success | real `TlsrPgm.py` commands where possible; everything else **exits non-zero** |
| L6 — non-existent `fetch` npm package | `uvx mcp-server-fetch` in this leaf's own settings layer (it bypasses `embedded-base`, so it declares `fetch` itself) |
| L7 — CI dispatch event name mismatch | this repo now listens for both `template-image-updated` and `base-image-updated` |
| L8 — silently drifting copied assets | `sync-shared-assets.sh --check` runs as a **blocking** `asset-drift` CI job here |
| L9 — irrelevant launch configurations | documented: there is no supported in-container GDB server for TC32, and `debugServer` says so and fails |
| 4.3 — real flashing | `pvvx/TLSRPGM` baked in at `$TLSR_TOOLS` |

Be clear-eyed about this leaf: `TlsrPgm.py` needs **dedicated programmer
hardware** (a TB-04-KIT or a TLSR8269 running the TLSRPGM firmware), not just a
USB-serial adapter, and there is still no in-container debugger. It is
materially weaker than `arm` and `wch`, and the docs now say so rather than
implying parity.
