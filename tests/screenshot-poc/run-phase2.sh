#!/usr/bin/env bash
# Archival manual runner for the off-tree Phase 2 screenshot-stream PoC.
# Not linked into meson.build. Compiles into /tmp and cleans up snappr-win on exit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WIN_HOST="${1:-snappr-win}"
CERT_DIR="/tmp/argus-shot-certs"

valac --pkg gio-2.0 --pkg gee-0.8 --pkg json-glib-1.0 --pkg libsoup-3.0 --pkg ocrpc \
	-X -locrpc -X -Wl,--export-dynamic "${SCRIPT_DIR}/relay.vala" -o /tmp/argus-shot-relay
valac --pkg gio-2.0 --pkg gee-0.8 --pkg json-glib-1.0 --pkg libsoup-3.0 --pkg gtk4 --pkg ocrpc \
	-X -locrpc "${SCRIPT_DIR}/viewer.vala" -o /tmp/argus-shot-viewer

if [[ ! -f "${CERT_DIR}/ca.crt" ]]; then
	mkdir -p "${CERT_DIR}"
	openssl req -x509 -newkey rsa:2048 -nodes -keyout "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.crt" -days 1 -subj "/CN=ArgusShotCA"
	for name in server agent view; do
		openssl req -newkey rsa:2048 -nodes -keyout "${CERT_DIR}/${name}.key" -out "${CERT_DIR}/${name}.csr" -subj "/CN=${name}"
		openssl x509 -req -in "${CERT_DIR}/${name}.csr" -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial -out "${CERT_DIR}/${name}.crt" -days 1
	done
fi

ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "mkdir -p /c/Users/alan/argus-shot-p2"'
scp -q "${SCRIPT_DIR}/worker.c" "${SCRIPT_DIR}/agent.vala" "${CERT_DIR}/ca.crt" "${CERT_DIR}/agent.crt" "${CERT_DIR}/agent.key" "${WIN_HOST}:C:/Users/alan/argus-shot-p2/"
ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/usr/bin:\$PATH; cd /c/Users/alan/argus-shot-p2 && gcc -O2 -Wall -o worker.exe worker.c -lws2_32 -lgdi32 -luser32 -ladvapi32 -lwtsapi32 -ljpeg && valac --pkg gio-2.0 --pkg gee-0.8 --pkg json-glib-1.0 --pkg libsoup-3.0 --pkg ocrpc --vapidir /ucrt64/share/vala/vapi -X -I/ucrt64/include -X -L/ucrt64/lib -X -locrpc agent.vala -o agent.exe && cp -f /ucrt64/bin/libjpeg-8.dll ."'

rm -f /tmp/argus-shot-relay.log /tmp/argus-shot-agent.log /tmp/argus-shot-viewer.log /tmp/argus-shot-phase2-before.png /tmp/argus-shot-phase2-after.png

/tmp/argus-shot-relay "${CERT_DIR}" 19443 > /tmp/argus-shot-relay.log 2>&1 &
RELAY_PID=$!

cleanup() {
	kill "${AGENT_SSH_PID:-}" 2>/dev/null || true
	kill "${RELAY_PID:-}" 2>/dev/null || true
	ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "export PATH=/usr/bin:/c/Windows/System32:\$PATH; MSYS_NO_PATHCONV=1 taskkill.exe /IM worker.exe /F 2>/dev/null || true; MSYS_NO_PATHCONV=1 taskkill.exe /IM agent.exe /F 2>/dev/null || true; sc.exe stop ArgusShotP2 2>/dev/null || true; sc.exe delete ArgusShotP2 2>/dev/null || true; rm -f /c/Users/alan/argus-shot-p2/worker.c /c/Users/alan/argus-shot-p2/agent.vala /c/Users/alan/argus-shot-p2/worker.exe /c/Users/alan/argus-shot-p2/agent.exe /c/Users/alan/argus-shot-p2/libjpeg-8.dll /c/Users/alan/argus-shot-p2/ca.crt /c/Users/alan/argus-shot-p2/agent.crt /c/Users/alan/argus-shot-p2/agent.key /c/Users/alan/argus-shot-p2/service.log /c/Users/alan/argus-shot-p2/worker.log && rmdir /c/Users/alan/argus-shot-p2 2>/dev/null || true"' >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in 1 2 3 4 5 6 7 8 9 10; do
	if grep -q "relay listening 19443" /tmp/argus-shot-relay.log 2>/dev/null; then
		break
	fi
	sleep 0.2
done

ssh -o ExitOnForwardFailure=yes -R 19443:127.0.0.1:19443 "${WIN_HOST}" \
	'C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/usr/bin:\$PATH; export GIO_MODULE_DIR=C:/msys64/ucrt64/lib/gio/modules; cd /c/Users/alan/argus-shot-p2 && ./agent.exe C:/Users/alan/argus-shot-p2 19443 19444"' \
	> /tmp/argus-shot-agent.log 2>&1 &
AGENT_SSH_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if grep -q "agent local_listening 19444" /tmp/argus-shot-agent.log 2>/dev/null; then
		break
	fi
	sleep 0.3
done

if ! grep -q "agent local_listening 19444" /tmp/argus-shot-agent.log 2>/dev/null; then
	echo "AGENT DID NOT START:"
	cat /tmp/argus-shot-agent.log
	cat /tmp/argus-shot-relay.log
	exit 1
fi

ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "export PATH=/usr/bin:/c/Windows/System32:\$PATH; sc.exe delete ArgusShotP2 2>/dev/null || true; sleep 0.5; sc.exe create ArgusShotP2 type= own start= demand binPath= \"C:\\Users\\alan\\argus-shot-p2\\worker.exe service\" >/dev/null && sc.exe start ArgusShotP2 >/dev/null"'

TARGETS=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	TARGETS="$(ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "grep -m1 ^targets /c/Users/alan/argus-shot-p2/worker.log 2>/dev/null || true"' | tr -d '\r')"
	if [[ -n "${TARGETS}" ]]; then
		break
	fi
	sleep 0.5
done

echo "DISCOVERED: ${TARGETS}"
BTN_XY="$(awk '{print $2}' <<< "${TARGETS}" | cut -d= -f2)"
EDIT_XY="$(awk '{print $3}' <<< "${TARGETS}" | cut -d= -f2)"
BTN_X="${BTN_XY%,*}"
BTN_Y="${BTN_XY#*,}"
EDIT_X="${EDIT_XY%,*}"
EDIT_Y="${EDIT_XY#*,}"

/tmp/argus-shot-viewer "${CERT_DIR}" 19443 "${BTN_X}" "${BTN_Y}" "${EDIT_X}" "${EDIT_Y}" 65 | tee /tmp/argus-shot-viewer.log

kill "${AGENT_SSH_PID:-}" 2>/dev/null || true
ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "export PATH=/usr/bin:/c/Windows/System32:\$PATH; MSYS_NO_PATHCONV=1 taskkill.exe /IM agent.exe /F 2>/dev/null || true"' >/dev/null 2>&1 || true
sleep 2
echo "=== RELAY LOG ==="
cat /tmp/argus-shot-relay.log
echo "=== AGENT LOG ==="
cat /tmp/argus-shot-agent.log
echo "=== WORKER LOG ==="
ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "cat /c/Users/alan/argus-shot-p2/worker.log 2>/dev/null || true"'
echo "=== SERVICE LOG ==="
ssh "${WIN_HOST}" 'C:\msys64\usr\bin\bash.exe -lc "cat /c/Users/alan/argus-shot-p2/service.log 2>/dev/null || true"'
ls -lh /tmp/argus-shot-phase2-before.png /tmp/argus-shot-phase2-after.png
