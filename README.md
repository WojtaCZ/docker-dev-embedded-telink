# docker-dev-embedded-telink

Telink TLSR8258 BLE development container. Targets the **TLSR8258** (TC32 architecture, 32-bit proprietary core, BLE 5.0).

Inherits directly from `docker-dev-template` (not `embedded-base`) because the tc32 toolchain is a 32-bit binary blob that requires `lib32-glibc`. This keeps that weight out of the shared ARM/RISC-V base image.

## Prerequisites: Telink SDK (required, not in this image)

The tc32 toolchain is distributed **inside the Telink BLE SDK**, which is proprietary and not redistributable. You must download it separately:

1. Go to the Telink wiki or [Ai-Thinker-Open/Telink_825X_SDK](https://github.com/Ai-Thinker-Open/Telink_825X_SDK) for the open-source mirror.
2. Place the SDK at `~/telink/Telink_825X_SDK` (or set `DEV_TELINK_SDK` to its path).
3. The `dev-up.sh` script mounts it read-only at `/opt/telink/sdk` inside the container.

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

## Flashing

Flashing TLSR8258 requires Telink's **SWS** (Single Wire Serial) protocol. Two options:

**Option 1: Telink BDT** (official, Windows GUI only)
- Not usable inside this container. Flash from the host.

**Option 2: BMP + community SWS tools** (Linux, experimental)
```bash
# Install tlsr_tools from: https://github.com/Ai-Thinker-Open/TLSR825x_Tools
# Then:
python3 /path/to/tlsr_term.py -p /dev/ttyACM0 flash -a 0x000000 firmware.bin
```

**Option 3: openocd** — not supported for TLSR8258/SWS natively.

## VSCode tasks

The shared task framework (`tasks.json`) is available via `/scaffold-mcu-project telink`. Task names are identical to other leaves (Build, Flash, Clean, etc.) but the Flash and Debug tasks are best-effort — point them at your chosen flashing tool in `.mcu-profile.json`.

## C++ notes

tc32-elf-g++ supports C++ classes and templates. The BLE SDK is written in C; wrap includes in `extern "C" { }`. No STL, no exceptions, no RTTI — the same rules as a tight bare-metal ARM project.

See the `tlsr8258-ble-stack` Claude skill for the SDK structure and the `tlsr-otp-vs-flash` skill for NVM usage.

## Template update propagation

This image tracks `ghcr.io/wojtacz/docker-dev-template:latest`. `dev-up.sh` passes `--pull` by default. CI rebuilds automatically via `repository_dispatch` (`template-image-updated` event) from `docker-dev-template`.
