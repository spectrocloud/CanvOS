FROM quay.io/kairos/ubuntu:20.04-core-arm64-nvidia-jetson-agx-orin-v2.4.3

RUN apt update && \
    apt upgrade -y
COPY --from=quay.io/kairos/framework:v2.4.5 / /
RUN kernel=$(ls /boot/Image* 2>/dev/null | head -n1) && if [ -e "$kernel" ]; then ln -sf "$kernel" /boot/vmlinuz; fi || true