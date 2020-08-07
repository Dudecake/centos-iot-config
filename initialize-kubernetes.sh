#!/bin/sh

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

set -e

if [[ ! $(grep -Fxq /usr/libexec/kubernetes /etc/fstab) ]]; then
    echo '/var/lib/kubernetes-volume-plugins /usr/libexec/kubernetes none bind 0 0' >> /etc/fstab
fi

mount /usr/libexec/kubernetes
exec kubeadm init --ignore-preflight-errors=swap $@
