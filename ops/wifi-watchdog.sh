#!/usr/bin/env bash
# Brings the Wi-Fi back when NetworkManager has given up on it.
#
# Run every two minutes by ops/systemd/wifi-watchdog.timer. On 2026-11-02 the
# router's 2.4 GHz radio went quiet, NetworkManager's one attempt at the 5 GHz
# radio timed out ("ssid-not-found"), and it never tried again: the site was
# off the internet for 21 hours until someone clicked the network by hand.
# Setting connection.autoconnect-retries to 0 (forever) on the profile is the
# first fix; this is the second, in case NetworkManager stalls some other way.
#
# It does nothing while a wired connection is up, or while the Wi-Fi is
# connected and the router answers. Otherwise it asks NetworkManager to
# connect the Wi-Fi device, which picks the best saved network itself, so no
# network name is written here. Each action is logged to the journal:
#   journalctl --user -u wifi-watchdog
set -u

dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2 == "wifi" { print $1; exit }')
[ -n "$dev" ] || exit 0

# A wired connection carries the site: leave the Wi-Fi alone.
if nmcli -t -f TYPE,STATE dev | grep -q '^ethernet:connected$'; then
  exit 0
fi

state=$(nmcli -t -f GENERAL.STATE dev show "$dev" | cut -d: -f2)

if [[ "$state" == 100* ]]; then
  gw=$(ip -4 route show default dev "$dev" | awk '{ print $3; exit }')
  if [ -n "$gw" ]; then
    for _ in 1 2 3; do
      ping -c 1 -W 2 -I "$dev" "$gw" > /dev/null 2>&1 && exit 0
      sleep 5
    done
    echo "router $gw not answering on $dev; reconnecting"
  else
    echo "$dev connected but has no default route; reconnecting"
  fi
else
  echo "$dev is '$state'; connecting"
fi

nmcli radio wifi on
nmcli --wait 45 device connect "$dev"
