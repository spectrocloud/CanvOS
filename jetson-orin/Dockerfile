FROM --platform=arm64 quay.io/kairos/ubuntu:20.04-core-arm64-nvidia-jetson-agx-orin-v3.0.5

# RUN apt update && \
#     apt upgrade -y
# COPY --from=quay.io/kairos/framework:v2.4.5 / /
# RUN kernel=$(ls /boot/Image* 2>/dev/null | head -n1) && if [ -e "$kernel" ]; then ln -sf "$kernel" /boot/vmlinuz; fi || true
# RUN echo 'omit_dracutmodules+=" iscsi "' > /etc/dracut.conf.d/iscsi.conf
COPY iscsi.conf /etc/dracut.conf.d/iscsi.conf