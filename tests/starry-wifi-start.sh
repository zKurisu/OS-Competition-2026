#!/bin/sh
# Runs on the StarryOS board from /root/init.sh. Credentials stay on the card.
set -eu
ssid=$(sed -n '1p' /root/akars-wifi.ssid)
psk=$(sed -n '1p' /root/akars-wifi.pass)
[ -n "$ssid" ] && [ -n "$psk" ]
/usr/bin/wifi_switch sta "$ssid" "$psk"
if command -v sshd >/dev/null 2>&1; then
  if ! pidof sshd >/dev/null 2>&1; then sshd; fi
fi
