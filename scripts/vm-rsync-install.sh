#!/usr/bin/env bash
# Rsync argusrm to the Ubuntu 26.04 QEMU guest and install server + agent binaries.
# Same SSH target pattern as gnome-shell-rpc (alan@192.168.122.115 / ubuntu2604).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="${REMOTE:-alan@192.168.122.115}"
REMOTE_ROOT="${REMOTE_ROOT:-gitlive/argusrm}"

echo "[vm-rsync-install] rsync -> ${REMOTE}:${REMOTE_ROOT}/"
rsync -az --delete \
	--exclude '.git/' \
	--exclude 'build/' \
	--exclude 'dist/' \
	--exclude 'dist-windows/' \
	--exclude '**/.cache/' \
	"${ROOT}/" \
	"${REMOTE}:${REMOTE_ROOT}/"

echo "[vm-rsync-install] build and install on guest"
ssh -o BatchMode=yes "${REMOTE}" "bash -s" -- "${REMOTE_ROOT}" <<'EOF'
set -euo pipefail
REMOTE_ROOT="$1"
cd ~/"${REMOTE_ROOT}"
if ! dpkg -l freerdp3-dev >/dev/null 2>&1 \
	|| ! dpkg -l libxlsxwriter-dev >/dev/null 2>&1 \
	|| ! dpkg -l libminizip-dev >/dev/null 2>&1; then
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		freerdp3-dev libocsqlite-dev libxlsxwriter-dev \
		zlib1g-dev libminizip-dev libssl-dev >/dev/null
fi
if [ ! -d build ]; then
	meson setup build
else
	meson setup build --reconfigure >/dev/null
fi
ninja -C build server/argusrm-server agent/argusrm-agent agent/argusrm-agent-gtk
sudo install -m 0755 build/server/argusrm-server /usr/bin/argusrm-server
sudo install -m 0755 build/agent/argusrm-agent /usr/bin/argusrm-agent
sudo install -m 0755 build/agent/argusrm-agent-gtk /usr/bin/argusrm-agent-gtk
if [ -f build/server/org.roojs.ArgusServer.register.policy ]; then
	sudo install -m 0644 build/server/org.roojs.ArgusServer.register.policy \
		/usr/share/polkit-1/actions/org.roojs.ArgusServer.register.policy
fi
if [ -f build/agent/org.roojs.ArgusAgent.register.policy ]; then
	sudo install -m 0644 build/agent/org.roojs.ArgusAgent.register.policy \
		/usr/share/polkit-1/actions/org.roojs.ArgusAgent.register.policy
fi
sudo install -m 0644 packaging/systemd/argusrm-server.service \
	/usr/lib/systemd/system/argusrm-server.service
sudo install -m 0644 packaging/systemd/argusrm-agent.service \
	/usr/lib/systemd/system/argusrm-agent.service 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl enable --now argusrm-server
sleep 3
systemctl is-active argusrm-server
stat -c '%y %n' /usr/bin/argusrm-agent-gtk /usr/bin/argusrm-server
EOF

echo "[vm-rsync-install] done — on the guest desktop run: argusrm-agent-gtk"