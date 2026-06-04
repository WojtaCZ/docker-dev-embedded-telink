# syntax=docker/dockerfile:1.7
# Telink TLSR8258 (TC32 architecture, BLE)
# Inherits FROM docker-dev-template directly (not from embedded-base) because
# the tc32 toolchain is a 32-bit binary blob that requires lib32-glibc.
# Keeping that multilib weight out of the shared embedded-base image.
FROM ghcr.io/wojtacz/docker-dev-template:latest

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
        jq \
        python \
        usbutils \
        picocom \
        tio \
        screen \
        minicom \
        openocd \
        stlink \
        gdb-multiarch \
        fakeroot \
        patch \
    && pacman -Scc --noconfirm

# AUR helper (paru-bin) for probe-rs and wlink (useful for BMP / SWS flashing)
RUN useradd -m aurbuild && echo "aurbuild ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/aurbuild
USER aurbuild
RUN cd /tmp && \
    git clone https://aur.archlinux.org/paru-bin.git && \
    cd paru-bin && makepkg -si --noconfirm && \
    rm -rf /tmp/paru-bin
USER root
RUN su aurbuild -c "paru -S --noconfirm --needed --skipreview blackmagic probe-rs-bin"

# udev rules (same set as embedded-base — for host install only)
COPY udev-rules/ /etc/udev/rules.d/
RUN groupadd -f plugdev && usermod -aG dialout,uucp,tty,plugdev,lock dev

# Telink SDK is EULA-restricted and not redistributable.
# Mount your downloaded Telink_825X_SDK at /opt/telink/sdk:
#   -v ~/telink/Telink_825X_SDK:/opt/telink/sdk
# The SDK ships the tc32 g++ binary blob under tools/tc32/bin/.
RUN mkdir -p /opt/telink && chown dev:dev /opt/telink

# run-profile-task.sh (same helper as embedded-base, copied here since we don't inherit it)
COPY run-profile-task.sh /opt/embedded/run-profile-task.sh
RUN chmod +x /opt/embedded/run-profile-task.sh
COPY vscode-templates/ /opt/embedded/vscode-templates/

# Default MCU profile
COPY profile.json /opt/embedded/profile.json

USER dev
ENV PATH="/opt/telink/sdk/tools/tc32/bin:${PATH}"

COPY --chown=dev:dev claude-embedded-telink/skills/      /home/dev/.claude/skills/
COPY --chown=dev:dev claude-embedded-telink/settings.json /home/dev/.claude/settings.json

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
