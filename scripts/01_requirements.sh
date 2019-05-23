#!/usr/bin/env bash

set -ex

export LC_ALL=C

source utils/logging.sh

sudo apt-get update

sudo apt-get install -y selinux-utils

if selinuxenabled ; then
    sudo setenforce permissive
    sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
fi

# Install required packages
sudo apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y install \
  crudini \
  curl \
  dnsmasq \
  figlet \
  golang \
  nmap \
  patch \
  psmisc \
  python-pip \
  python-requests \
  python-setuptools \
  wget \
  jq \
  libguestfs-tools \
  libvirt-bin \
  libvirt-dev \
  nodejs \
  podman \
  python-dev \
  python-lxml \
  python-netaddr \
  python-pip \
  qemu-kvm \
  virtinst \
  unzip \
  bridge-utils \
  yarn

# Install python packages not included as rpms
sudo pip install \
  lolcat \
  yq \
  virtualbmc \
  python-ironicclient \
  python-ironic-inspector-client \
  python-openstackclient \
  ansible \
  ara


if ! which k3s 2>/dev/null ; then
   curl -LO https://github.com/rancher/k3s/releases/download/v0.5.0/k3s \
	&& sudo install k3s /usr/local/bin/

fi

if ! which docker-machine-driver-kvm2 >/dev/null ; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2 \
          && sudo install docker-machine-driver-kvm2 /usr/local/bin/
fi

if ! which kubectl 2>/dev/null ; then
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
        && chmod +x kubectl && sudo mv kubectl /usr/local/bin/.
fi

sudo systemctl status libvirtd

sudo usermod -a -G libvirtd $(whoami)

newgrp libvirtd <<EONG
# some of this not required on ubuntu
# virsh net-define /etc/libvirt/qemu/networks/default.xml
virsh net-autostart default
# virsh net-start default
EONG

sudo bash -c 'echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/50-default.conf'
sudo /sbin/sysctl -p
