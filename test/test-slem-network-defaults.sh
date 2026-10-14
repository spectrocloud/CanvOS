#!/bin/bash
# Exercises the default DHCP networkd config shipped by slem/5.5 against a real
# systemd-networkd, on a three-NIC host, including precedence against Stylus config.
#
#   ./test/test-slem-network-defaults.sh [image]
#
# Default image is the one slem/5.5/build.sh produces. Requires a Docker daemon
# able to run privileged containers.

set -euo pipefail

IMAGE="${1:-slem-kairos:5.5}"
FAILURES=0

fail() {
	echo "FAIL: $*" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	echo "ok: $*"
}

# Runs a payload inside the image with three veth NIC pairs; each peer is served
# by the same networkd instance acting as a DHCP server, so the NIC side sees a
# real lease. Echoes the payload's stdout.
in_image() {
	docker run --rm --privileged --network none --entrypoint /bin/sh "$IMAGE" -c "
systemd-machine-id-setup >/dev/null 2>&1 || true
mkdir -p /run/dbus && dbus-daemon --system --fork >/dev/null 2>&1 || true
/usr/lib/systemd/systemd-udevd --daemon
$1
/usr/lib/systemd/systemd-networkd >/tmp/networkd.log 2>&1 &
sleep 10
$2
" 2>/dev/null
}

# Three NICs plus one legacy-named and one container-style link, each NIC paired
# with a DHCP server peer on its own subnet.
make_links() {
	cat <<-'EOF'
		for i in 1 2 3; do
		  ip link add "enp${i}s0" type veth peer name "srv${i}"
		  printf '[Match]\nName=srv%s\n[Network]\nAddress=10.99.%s.1/24\nDHCPServer=yes\n' "$i" "$i" \
		    > /etc/systemd/network/00-test-srv${i}.network
		done
		ip link add eth9 type veth peer name srv9
		printf '[Match]\nName=srv9\n[Network]\nAddress=10.99.9.1/24\nDHCPServer=yes\n' \
		  > /etc/systemd/network/00-test-srv9.network
		ip link add vz-test type dummy
	EOF
}

network_file() {
	echo "networkctl status $1 2>/dev/null | sed -n 's/.*Network File: //p' | tr -d ' '"
}

echo "== image under test: ${IMAGE}"

echo
echo "-- the image ships the default DHCP config"
SHIPPED=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'ls /usr/lib/systemd/network/ | grep dhcp | sort | tr "\n" " "' 2>/dev/null)
if [ "$SHIPPED" = "20-dhcp-legacy.network 20-dhcp.network " ]; then
	pass "/usr/lib/systemd/network ships 20-dhcp.network and 20-dhcp-legacy.network"
else
	fail "expected 20-dhcp.network and 20-dhcp-legacy.network in /usr/lib/systemd/network, got: ${SHIPPED:-none}"
fi

echo
echo "-- without the config every physical NIC is unmanaged (the reported defect)"
OUT=$(in_image "$(make_links)
mv /usr/lib/systemd/network/20-dhcp.network /tmp/
mv /usr/lib/systemd/network/20-dhcp-legacy.network /tmp/" \
	'networkctl list --no-legend 2>/dev/null | awk "\$2 ~ /^enp/ {print \$2\"=\"\$5}" | sort | tr "\n" " "')
if echo "$OUT" | grep -q "enp1s0=unmanaged .*enp2s0=unmanaged .*enp3s0=unmanaged"; then
	pass "defect reproduced without the config: $OUT"
else
	fail "expected all enp* unmanaged without the config, got: $OUT"
fi

echo
echo "-- with the config all three NICs are managed, configured and hold a DHCP lease"
OUT=$(in_image "$(make_links)" '
echo "setup=$(networkctl list --no-legend 2>/dev/null | awk "\$2 ~ /^enp/ {print \$2\"=\"\$5}" | sort | tr "\n" " ")"
echo "addrs=$(ip -br addr show | awk "\$1 ~ /^enp/ {print \$1\"=\"\$3}" | sort | tr "\n" " ")"
/usr/lib/systemd/systemd-networkd-wait-online --timeout=30 >/dev/null 2>&1
echo "wait-online=$?"')
SETUP=$(echo "$OUT" | grep '^setup=')
ADDRS=$(echo "$OUT" | grep '^addrs=')
WAIT=$(echo "$OUT" | grep '^wait-online=')
if echo "$SETUP" | grep -q "enp1s0=configured .*enp2s0=configured .*enp3s0=configured"; then
	pass "all three NICs managed and configured: $SETUP"
else
	fail "expected all enp* configured, got: $SETUP"
fi
for i in 1 2 3; do
	if echo "$ADDRS" | grep -qE "enp${i}s0@[^=]*=10\.99\.${i}\.[0-9]+/24"; then
		pass "enp${i}s0 holds a DHCP lease from its own subnet"
	else
		fail "enp${i}s0 has no 10.99.${i}.0/24 DHCP lease: $ADDRS"
	fi
done
if [ "$WAIT" = "wait-online=0" ]; then
	pass "systemd-networkd-wait-online succeeds on a three-NIC host"
else
	fail "systemd-networkd-wait-online did not succeed: $WAIT"
fi

echo
echo "-- the config claims en* and eth* and nothing else"
OUT=$(in_image "$(make_links)" "
echo \"enp1s0=\$($(network_file enp1s0))\"
echo \"eth9=\$($(network_file eth9))\"
networkctl list --no-legend 2>/dev/null | while read -r _ link _ _ setup; do echo \"\$link=\$setup\"; done")
if echo "$OUT" | grep -q "^enp1s0=/usr/lib/systemd/network/20-dhcp.network$"; then
	pass "enp1s0 matched by 20-dhcp.network"
else
	fail "enp1s0 not matched by the shipped 20-dhcp.network: $(echo "$OUT" | grep '^enp1s0=')"
fi
if echo "$OUT" | grep -q "^eth9=/usr/lib/systemd/network/20-dhcp-legacy.network$"; then
	pass "eth9 matched by 20-dhcp-legacy.network"
else
	fail "eth9 not matched by the shipped 20-dhcp-legacy.network: $(echo "$OUT" | grep '^eth9=')"
fi
if echo "$OUT" | grep -q "^lo=unmanaged$"; then
	pass "loopback left unmanaged"
else
	fail "loopback should stay unmanaged: $(echo "$OUT" | grep '^lo=')"
fi
if echo "$OUT" | grep -q "^vz-test=unmanaged$"; then
	pass "container-style link left unmanaged"
else
	fail "vz-test should stay unmanaged: $(echo "$OUT" | grep '^vz-test=')"
fi

echo
echo "-- Stylus per-interface config wins, unlisted NICs still get DHCP"
OUT=$(in_image "$(make_links)
printf '[Match]\nName=enp2s0\n[Network]\nAddress=192.168.77.5/24\nGateway=192.168.77.1\n' \
  > /etc/systemd/network/10-enp2s0.network" "
echo \"enp1s0=\$($(network_file enp1s0))\"
echo \"enp2s0=\$($(network_file enp2s0))\"
ip -br addr show enp2s0 | awk '{print \"enp2s0-addr=\"\$3}'
ip -br addr show enp1s0 | awk '{print \"enp1s0-addr=\"\$3}'")
if echo "$OUT" | grep -q "^enp2s0=/etc/systemd/network/10-enp2s0.network$"; then
	pass "10-enp2s0.network beats the shipped 20-dhcp.network"
else
	fail "Stylus 10-<iface>.network did not win: $(echo "$OUT" | grep '^enp2s0=')"
fi
if echo "$OUT" | grep -q "^enp2s0-addr=192.168.77.5/24$"; then
	pass "enp2s0 took the operator's static address"
else
	fail "enp2s0 did not take the static address: $(echo "$OUT" | grep '^enp2s0-addr=')"
fi
if echo "$OUT" | grep -q "^enp1s0=/usr/lib/systemd/network/20-dhcp.network$"; then
	pass "unlisted enp1s0 still falls back to DHCP"
else
	fail "unlisted enp1s0 lost its DHCP default: $(echo "$OUT" | grep '^enp1s0=')"
fi
if echo "$OUT" | grep -qE "^enp1s0-addr=10\.99\.1\.[0-9]+/24$"; then
	pass "unlisted enp1s0 still holds a DHCP lease alongside the static NIC"
else
	fail "unlisted enp1s0 has no DHCP lease: $(echo "$OUT" | grep '^enp1s0-addr=')"
fi

echo
echo "-- an /etc copy of the same name takes precedence over the /usr/lib default"
OUT=$(in_image "$(make_links)
printf '[Match]\nName=en*\n[Network]\nAddress=192.168.88.9/24\n' \
  > /etc/systemd/network/20-dhcp.network" "
echo \"enp1s0=\$($(network_file enp1s0))\"
ip -br addr show enp1s0 | awk '{print \"enp1s0-addr=\"\$3}'")
if echo "$OUT" | grep -q "^enp1s0=/etc/systemd/network/20-dhcp.network$"; then
	pass "/etc/systemd/network/20-dhcp.network masks the /usr/lib default"
else
	fail "same-name /etc file did not mask the /usr/lib default: $(echo "$OUT" | grep '^enp1s0=')"
fi
if echo "$OUT" | grep -q "^enp1s0-addr=192.168.88.9/24$"; then
	pass "the masking file's settings are the ones applied"
else
	fail "masking file's settings not applied: $(echo "$OUT" | grep '^enp1s0-addr=')"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
	echo "PASS"
else
	echo "FAILED: ${FAILURES} check(s)"
	exit 1
fi
