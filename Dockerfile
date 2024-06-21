FROM quay.io/kairos/core-ubuntu-22-lts:latest as base
RUN mkdir -p /run/lock
RUN touch /usr/libexec/.keep

RUN mkdir -p /var/cache/apt/archives/partial

# Add the Kubernetes repository key
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes repository
RUN echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    containerd \
    runc \
    kubelet \
    kubeadm \
    kubectl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/containerd/

COPY assets/90-override.conf /etc/sysctl.d/90-override.conf
COPY assets/netfilter.conf /etc/modules-load.d/netfilter.conf
COPY assets/config.toml /etc/containerd/config.toml

# Copy the Kairos framework files. We use master builds here for fedora. See https://quay.io/repository/kairos/framework?tab=tags for a list
COPY --from=quay.io/kairos/framework:master_ubuntu-22-lts / /

# Set the Kairos arguments in os-release file to identify your Kairos image
FROM quay.io/kairos/osbuilder-tools:latest as osbuilder
RUN zypper install -y gettext
RUN mkdir /workspace
COPY --from=base /etc/os-release /workspace/os-release
# You should change the following values according to your own versioning and other details
RUN OS_NAME=kairos-vadim-ubuntu \
  OS_VERSION=v1.0.0 \
  OS_ID="kairos" \
  BUG_REPORT_URL="https://github.com/natrontech/n8s/issues" \
  HOME_URL="https://github.com/natrontech/n8s" \
  OS_REPO="quay.io/vadimzharov/core-ubuntu" \
  OS_LABEL="latest" \
  GITHUB_REPO="natrontech/n8s" \
  VARIANT="core" \
  FLAVOR="ubuntu" \
  /update-os-release.sh

FROM base
COPY --from=osbuilder /workspace/os-release /etc/os-release

# Activate Kairos services
RUN systemctl enable cos-setup-reconcile.timer && \
          systemctl enable cos-setup-fs.service && \
          systemctl enable cos-setup-boot.service && \
          systemctl enable cos-setup-network.service

## Generate initrd
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -v -N -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd && depmod -a "${kernel}"
RUN rm -rf /boot/initramfs-*