#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
KEY=${KEY:-920498D5E1E4D38C258A1AE623FE6D6C9114BC76}
DIST_NAME=iot
REPO_PATH=${REPO_PATH:-/var/lib/ostree/iot}
DIST_PATH=${DIST_PATH:-/var/lib/ostree/dist}

set -e
if [[ ! -d /var/cache/ostree/zfs ]]; then
  mkdir /var/cache/ostree/zfs
fi
pushd /var/cache/ostree/zfs > /dev/null
ZFS_VERSION=$(dnf info zfs --disablerepo=\* --enablerepo=zfs | grep -Po '(?<=zfs-).+(?=\.(fc|el))')
MACHINE="$(uname -m)"
if [[ ! -f zfs-dkms-${ZFS_VERSION}.el8.src.rpm ]]; then
  UPDATE_REPO=1
  rm -rf ./*
  curl -L --remote-name-all http://download.zfsonlinux.org/epel/8.2/SRPMS/zfs-${ZFS_VERSION}.el8.src.rpm http://download.zfsonlinux.org/epel/8.2/x86_64/zfs-dkms-${ZFS_VERSION}.el8.noarch.rpm
  mock -r centos-8-${MACHINE} rebuild zfs-${ZFS_VERSION}.*.src.rpm --resultdir .
  createrepo .
fi
[[ ${MACHINE} == "x86_64" ]] && MACHINE="amd64"
[[ ${MACHINE} == "aarch64" ]] && MACHINE="arm64"
popd > /dev/null

if [[ ${MACHINE} == "amd64" || ${MACHINE} == "arm64" || ${MACHINE} == "ppc64le" ]]; then
  echo "Checking latest Kubernetes version..." >&2
  KUBERNETES_RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
  echo "Latest version is ${KUBERNETES_RELEASE}" >&2
  if [[ ! -f kubernetes-server-linux-${MACHINE}-${KUBERNETES_RELEASE}.tar.gz ]]; then
    rm kubernetes-server-linux-*-*.tar.gz
    echo "Downloading latest Kubernetes version" >&2
    curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/kubernetes-server-linux-${MACHINE}.tar.gz -o kubernetes-server-linux-${MACHINE}-${KUBERNETES_RELEASE}.tar.gz
    tar --strip-components=3 -xf kubernetes-server-linux-${MACHINE}-${KUBERNETES_RELEASE}.tar.gz
  fi
  echo "Checking latest crictl version..." >&2
  CRICTL_RELEASE="$(curl -sS https://github.com/kubernetes-sigs/cri-tools/releases/latest | grep -oP 'v\d\.\d{2}\.\d')"
  echo "Latest version is ${CRICTL_RELEASE}" >&2
  if [[ ! -f crictl-${CRICTL_RELEASE}-linux-${MACHINE}.tar.gz ]]; then
    rm crictl-*-linux-*.tar.gz
    echo "Downloading latest crictl version" >&2
    curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_RELEASE}/crictl-${CRICTL_RELEASE}-linux-${MACHINE}.tar.gz
    tar -xf crictl-${CRICTL_RELEASE}-linux-${MACHINE}.tar.gz
  fi
else
  echo "Invalid arch ${MACHINE}" >&2
  exit 1
fi

if [[ ! -d "${REPO_PATH}"/tmp ]]; then
  ostree init --repo="${REPO_PATH}"
  NEW_REPO=1
fi
rm -rf ${REPO_PATH}/tmp/*.tmp
rpm-ostree compose tree --repo="${REPO_PATH}" --workdir "${REPO_PATH}/tmp" "${DIR}/centos-iot.yaml"
if [[ ! -z "${NEW_REPO}" ]]; then
  ostree --repo="${REPO_PATH}" static-delta generate centos/8/${MACHINE}/${DIST_NAME}
fi
#ostree --repo="${REPO_PATH}" gpg-sign centos/8/${MACHINE}/${DIST_NAME} ${KEY}
if [[ ! -d "${DIST_PATH}/tmp" ]]; then
  ostree init --repo="${DIST_PATH}" --mode=archive
fi
ostree --repo="${DIST_PATH}" pull-local "${REPO_PATH}"
ostree --repo="${DIST_PATH}" summary -u
# Deploy with
# ostree remote add centos-iot http://${URL}/ostree/iot
# ostree pull centos-iot:centos/8/${MACHINE}/${DIST_NAME}
# ostree admin deploy centos-iot:centos/8/${MACHINE}/${DIST_NAME}
