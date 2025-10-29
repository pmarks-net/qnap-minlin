SSH_SERVER=nasport-server.example.com
SSH_PORT=22
SSH_USER=nasport
RSYNC_PORT=9873
RSYNC_UID=example
RSYNC_GID=everyone
RSYNC_PATH=/share/Public
TIMEOUT=60

read -r -d '' PRIVATE_KEY <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
EOF

KEYFILE="$(mktemp)"
chmod 600 "$KEYFILE"
echo "$PRIVATE_KEY" >"$KEYFILE"

EXPECT_KEY="ssh-ed25519 ..."
KNOWN_HOSTS="$(mktemp)"
echo "$SSH_SERVER $EXPECT_KEY" >"$KNOWN_HOSTS"

# Launch rsync daemon immediately.
RSYNC_CONF="$(mktemp)"
cat >"$RSYNC_CONF" <<EOF
uid = $RSYNC_UID
gid = $RSYNC_GID
address = 127.0.0.1
use chroot = no
max connections = 2
log file = /dev/null
pid file = /tmp/rsyncd.pid
lock file = /tmp/rsyncd.lock

[disk]
  path = $RSYNC_PATH
  comment = QNAP disk
  read only = false
  list = yes
EOF
rsync --daemon --sever-mode=0 --port=$RSYNC_PORT --config="$RSYNC_CONF"

# Launch reverse ssh daemon immediately.
(
while true; do
  echo "$(date): Starting SSH tunnel to $SSH_SERVER:$SSH_PORT"
  ssh -N \
    -R 9022:localhost:22 \
    -R $RSYNC_PORT:localhost:$RSYNC_PORT \
    -p "$SSH_PORT" \
    -i "$KEYFILE" \
    -o "UserKnownHostsFile=$KNOWN_HOSTS" \
    -o "StrictHostKeyChecking=yes" \
    -o "ConnectTimeout=$TIMEOUT" \
    -o "ServerAliveInterval=$TIMEOUT" \
    -o "ServerAliveCountMax=3" \
    -o "ExitOnForwardFailure=yes" \
    "$SSH_USER@$SSH_SERVER"
  echo "$(date): SSH tunnel disconnected, retrying in 10 seconds..."
  sleep 10
done
) &

## Prepare minimal linux environment ##

cat >/tmp/dhclient.sh <<'EOF'
#!/bin/bash

make_resolv_conf() {
  local tmp=/etc/resolv.conf.dhclient-new
  rm -f $tmp
  if [ -n "$new_domain_name_servers" ]; then
    for ns in $new_domain_name_servers; do
      echo "nameserver $ns" >>$tmp
    done
  fi
  mv -f $tmp /etc/resolv.conf
}

case "$reason" in
  PREINIT)
    ip link set dev $interface up
    ;;
  BOUND|RENEW|REBIND|REBOOT)
    ip -4 route flush dev $interface
    if [ -n "$new_ip_address" ]; then
      ip -4 addr add ${new_ip_address}${new_subnet_mask:+/$new_subnet_mask} \
        ${new_broadcast_address:+broadcast $new_broadcast_address} \
        dev $interface
    fi
    if [ -n "$old_ip_address" ] && [ "$old_ip_address" != "$new_ip_address" ]; then
      ip -4 addr del $old_ip_address dev $interface
    fi
    for r in $new_routers; do
      ip -4 route add default via $r dev $interface && break
    done
    make_resolv_conf
    /sbin/hal_app --se_buzzer enc_id=0,mode=0  # beep
    ;;
  EXPIRE|FAIL|RELEASE|STOP)
    ip -4 addr flush dev $interface
    ip -4 route flush dev $interface
    ;;
esac
exit 0
EOF
chmod +x /tmp/dhclient.sh

cat >/tmp/ifplugd.sh <<'EOF'
#!/bin/sh
IFACE="$1"
ACTION="$2"
LEASE=/tmp/dhclient.lease
case "$ACTION" in
  up)
    dhclient -nw -4 -v -lf "$LEASE" -sf /tmp/dhclient.sh -cf /dev/null "$IFACE"
    ;;
  down)
    killall dhclient
    ;;
esac
exit 0
EOF
chmod +x /tmp/ifplugd.sh

cat >/tmp/minlin.sh <<'EOF'
#!/bin/sh
for sig in SIGTERM SIGKILL; do
  ps >/tmp/ps
  grep -v -E '\b(PID|init|ps|ssh|sshd|minlin|rsync|qWatchdogd|getty|bash)\b|init_nas|-sh|udev|hal| \[' /tmp/ps >/tmp/pskill
  cat /tmp/pskill
  awk '{print $1}' /tmp/pskill | xargs -n1 kill -$sig
  sleep 5
done
mount -o remount,ro /mnt/HDA_ROOT
busybox ifplugd -s -t1 -u1 -d1 -i eth0 -r /tmp/ifplugd.sh
# for faster reboot:
echo -e '#!/bin/sh\ntouch /var/qfunc/qpkg.shutdown.finish' >/sbin/qpkg_cli
rm /tmp/minlin.sh
EOF

# After 10 minutes, pivot to minimal linux.
chmod +x /tmp/minlin.sh
(
  sleep 600
  /tmp/minlin.sh
) &
