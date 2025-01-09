#!/usr/bin/env bash
set -euo pipefail

export ARCH="${ARCH-amd64}"
export RUNC_VERSION="${RUNC_VERSION-v1.2.4}"
SCRIPTFOLDER="$(dirname "$(readlink -f "$0")")"
ONLY_CONTAINERD="${ONLY_CONTAINERD:-0}"

if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 VERSION SYSEXTNAME"
  echo "The script will download the containerd release tar ball and create a sysext squashfs image with the name SYSEXTNAME.raw in the current folder."
  echo "A temporary directory named SYSEXTNAME in the current folder will be created and deleted again."
  echo "All files in the sysext image will be owned by root."
  echo "The necessary systemd services will be created by this script"
  echo "To use arm64 pass 'ARCH=arm64' as environment variable (current value is '${ARCH}')."
  "${SCRIPTFOLDER}"/bake.sh --help
  exit 1
fi

VERSION="$1"
SYSEXTNAME="$2"

rm -f "containerd-${VERSION}.tgz"
curl -o "containerd-${VERSION}.tgz" -fsSL "https://github.com/containerd/containerd/releases/download/v${VERSION}/containerd-${VERSION}-linux-${ARCH}.tar.gz"
rm -f runc${ARCH}
curl -o runc -fsSL "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${ARCH}"
rm -rf "${SYSEXTNAME}"
mkdir -p "${SYSEXTNAME}"
tar --force-local -xf "containerd-${VERSION}.tgz" -C "${SYSEXTNAME}"
rm "containerd-${VERSION}.tgz"
mkdir -p "${SYSEXTNAME}"/usr/bin
mv "${SYSEXTNAME}"/bin/* "${SYSEXTNAME}"/usr/bin/
chmod +x runc
mv runc "${SYSEXTNAME}"/usr/bin
rmdir "${SYSEXTNAME}"/bin
mkdir -p "${SYSEXTNAME}/usr/lib/systemd/system"

cat > "${SYSEXTNAME}/usr/lib/systemd/system/containerd.service" <<-'EOF'
	[Unit]
	Description=containerd container runtime
	After=network.target
	[Service]
	Delegate=yes
	Environment=CONTAINERD_CONFIG=/usr/share/containerd/config.toml
	ExecStart=/usr/bin/containerd --config ${CONTAINERD_CONFIG}
	KillMode=process
	Restart=always
	# (lack of) limits from the upstream docker service unit
	LimitNOFILE=1048576
	LimitNPROC=infinity
	LimitCORE=infinity
	TasksMax=infinity
	[Install]
	WantedBy=multi-user.target
EOF
  mkdir -p "${SYSEXTNAME}/usr/lib/systemd/system/multi-user.target.d"
  { echo "[Unit]"; echo "Upholds=containerd.service"; } > "${SYSEXTNAME}/usr/lib/systemd/system/multi-user.target.d/10-containerd-service.conf"
  mkdir -p "${SYSEXTNAME}/usr/share/containerd"
  cat > "${SYSEXTNAME}/usr/share/containerd/config.toml" <<-'EOF'
	version = 2
	# set containerd's OOM score
	oom_score = -999
	[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
	# setting runc.options unsets parent settings
	runtime_type = "io.containerd.runc.v2"
	[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
	SystemdCgroup = true
EOF
sed 's/SystemdCgroup = true/SystemdCgroup = false/g' "${SYSEXTNAME}/usr/share/containerd/config.toml" > "${SYSEXTNAME}/usr/share/containerd/config-cgroupfs.toml"

RELOAD=1 "${SCRIPTFOLDER}"/bake.sh "${SYSEXTNAME}"
rm -rf "${SYSEXTNAME}"

mv "${SYSEXTNAME}.raw" "${SYSEXTNAME}-${VERSION}.raw"

cat > containerd.conf << EOF
[Transfer]
Verify=false
[Source]
Type=url-file
Path=https://github.com/ninech/containerd-sysext/releases/${TAG}/download/
MatchPattern=${SYSEXTNAME}-@v.raw
[Target]
InstancesMax=3
Type=regular-file
Path=/opt/extensions/containerd
CurrentSymlink=/etc/extensions/containerd.raw
EOF

sha256sum *.raw | tee SHA256SUMS
