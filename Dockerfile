# syntax=docker/dockerfile:1.7
# Telink TLSR8258 (TC32 architecture, BLE)
#
# Inherits FROM docker-dev-template directly (not from embedded-base) because
# the tc32 toolchain is a 32-bit binary blob that requires lib32-glibc.
# Keeping that multilib weight out of the shared embedded-base image.
#
# The cost is duplication: udev-rules/, run-profile-task.sh, vscode-templates/,
# profile.schema.json and cmake/ are copies owned by docker-dev-embedded-base.
# Resync them with that repo's scripts/sync-shared-assets.sh; its CI reports
# drift on every push.
ARG BASE_TAG=latest
FROM ghcr.io/wojtacz/docker-dev-template:${BASE_TAG}

USER root

# Enable multilib for the tc32 32-bit binary toolchain
RUN sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        lib32-glibc \
        lib32-gcc-libs \
        make \
        cmake \
        ninja \
        meson \
        jq \
        python \
        python-pyserial \
        usbutils \
        libusb \
        picocom \
        screen \
        minicom \
        socat \
        openocd \
        stlink \
        probe-rs \
        gdb \
        gtest \
        catch2 \
        gcovr \
        dfu-util \
    && pacman -Scc --noconfirm

# Package-name notes, all verified against the official Arch repos:
#   * `gdb`, not `gdb-multiarch` — that is the Debian name and does not exist
#     on Arch. Arch's gdb is built --enable-targets=all, so it IS multiarch.
#   * `probe-rs` is in `extra`; there is no `probe-rs-bin` AUR package.
#   * There is no `blackmagic` AUR package, and BMP needs no host package —
#     it presents a GDB server directly on /dev/ttyACM0.
#   * `tio` is AUR-only; picocom/minicom/screen/socat cover the same ground.
# With those fixed this image needs no AUR helper at all, so the paru-bin
# bootstrap is gone.

# udev rules for host install only (udev does not run inside a container)
COPY udev-rules/ /opt/embedded/udev-rules/
COPY scripts/install-host-udev-rules.sh /opt/embedded/install-host-udev-rules.sh
RUN chmod +x /opt/embedded/install-host-udev-rules.sh && \
    groupadd -f plugdev && usermod -aG dialout,uucp,tty,plugdev,lock dev

# Telink SDK is EULA-restricted and not redistributable, so this image ships a
# mount point rather than a compiler. Mount your downloaded SDK:
#   -v ~/telink/Telink_825X_SDK:/opt/telink/sdk:ro
# It carries the tc32 g++ binary blob under tools/tc32/bin/.
RUN mkdir -p /opt/telink && chown dev:dev /opt/telink

# Shared assets (copies — see the header comment)
COPY run-profile-task.sh   /opt/embedded/run-profile-task.sh
COPY profile.schema.json   /opt/embedded/profile.schema.json
COPY profile.json          /opt/embedded/profile.json
RUN chmod +x /opt/embedded/run-profile-task.sh && \
    ln -sf /opt/embedded/run-profile-task.sh /usr/local/bin/mcu
COPY vscode-templates/ /opt/embedded/vscode-templates/
COPY cmake/            /opt/embedded/cmake/

# TLSR825x SWS flashing tools (community; Telink's own BDT is Windows-GUI only).
# pvvx/TLSRPGM drives a SWire programmer over a serial port. NOTE it needs
# dedicated programmer hardware (a TB-04-KIT or TLSR8269 running the TLSRPGM
# firmware) wired PD3->RESET, PD4<->SWS, PB4->Power — a bare USB-serial adapter
# is not enough. Cloned rather than vendored so provenance stays visible.
ARG TLSR_TOOLS_REF=main
RUN git clone --depth=1 --branch "${TLSR_TOOLS_REF}" \
        https://github.com/pvvx/TLSRPGM /opt/telink/tlsr-tools 2>/dev/null \
     || echo "WARN: TLSRPGM clone failed; flashing will need the host BDT" && \
    rm -rf /opt/telink/tlsr-tools/.git
ENV TLSR_TOOLS=/opt/telink/tlsr-tools

# dev-doctor checks contributed by this layer
COPY dev-doctor-checks/ /opt/dev-doctor/checks.d/
RUN chmod +x /opt/dev-doctor/checks.d/*.sh

USER dev
ENV PATH="/opt/telink/sdk/tools/tc32/bin:${PATH}" \
    CROSS_PREFIX=tc32-elf-

COPY --chown=dev:dev claude-embedded-telink/skills/   /home/dev/.claude/skills/
COPY --chown=dev:dev claude-embedded-telink/commands/ /home/dev/.claude/commands/
COPY --chown=dev:dev claude-embedded-telink/settings.layer.json \
     /home/dev/.claude-layers/20-telink.json

# Memory layer: the Telink/tc32 inventory, concatenated into ~/.claude/CLAUDE.md
# by entrypoint.sh. Records that the compiler is MOUNTED, not installed.
COPY --chown=dev:dev claude-embedded-telink/CLAUDE.layer.md \
     /home/dev/.claude-memory-layers/20-telink.md

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
