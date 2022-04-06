#!/usr/local/bin/bash
#
# Wireguard reresolve-dns for OPNsense
# Based on reresolve-dns.sh in wireguard-tools by Jason A. Donenfeld <Jason@zx2c4.com>
#
# Copyright (c) 2021 Micha LaQua <micha.laqua@gmail.com>
#
# This belongs into /usr/local/bin/wg-reresolve-dns.sh

shopt -s nocasematch
shopt -s extglob

LOG_TAG="wg-reresolve-dns"

log () {
  echo "$1: $2"
  logger -p "user.$1" -t "$LOG_TAG" "$2"
}

process_peer() {
  interface=$1
  pubkey=$2
  endpoint=$3
  if [[ -z $pubkey ]] || [[ -z $endpoint ]]; then
    # No need for action, no endpoint set
    return 0
  fi
  handshake_info=$(wg show "$interface" latest-handshakes 2>&1)
  if [[ ! $handshake_info =~ ${pubkey//+/\\+} ]]; then
    log "error" "Interface $interface seems to be configured incorrectly for pubkey $pubkey ($handshake_info)"
    return 1
  fi
  latest_handshake=$(wg show "$interface" latest-handshakes | grep "$pubkey" | awk '{print $2}')
  if [[ $(($(date +%s) - $latest_handshake)) -lt 135 ]]; then
    # latest handshake is recent enough
    return 0
  fi
  endpoint_raw_old=$(wg show "$interface" endpoints | grep "$pubkey" | awk '{print $2}')
  wg set "$interface" peer "$pubkey" endpoint "$endpoint"
  if [[ $? -ne 0 ]]; then
    log "warning" "[$interface] Failure while re-resolving endpoint $endpoint for peer $pubkey"
    return 1
  fi
  endpoint_raw_new=$(wg show "$interface" endpoints | grep "$pubkey" | awk '{print $2}')
  if [[ "$endpoint_raw_old" != "$endpoint_raw_new" ]]; then
    log "notice" "[$interface] Successfully re-resolved endpoint $endpoint for peer $pubkey to $endpoint_raw_new"
  fi
  return 0
}

process_interface() {
  config_file=$1
  interface="$(basename $config_file .conf)"
  parse_peer_section=0
  pubkey=""
  endpoint=""
  while read -r line || [[ -n $line ]]; do
    stripped="${line%%\#*}"
    key="${stripped%%=*}"; key="${key##*([[:space:]])}"; key="${key%%*([[:space:]])}"
    value="${stripped#*=}"; value="${value##*([[:space:]])}"; value="${value%%*([[:space:]])}"
    if [[ $key == "["* ]] && [[ $parse_peer_section -eq 1 ]]; then
      process_peer $interface $pubkey $endpoint
      parse_peer_section=0
      pubkey=""
      endpoint=""
    fi
    if [[ $key == "[Peer]" ]]; then
      parse_peer_section=1
      continue
    fi
    if [[ $parse_peer_section -eq 1 ]]; then
      if [[ "$key" == "PublicKey" ]]; then
        pubkey="$value"
        continue
      elif [[ "$key" == "Endpoint" ]]; then
        endpoint="$value"
        continue
      fi
    fi
  done < "$config_file"
  if [[ $parse_peer_section -eq 1 ]]; then
    process_peer $interface $pubkey $endpoint
  fi
}

for config_file in /usr/local/etc/wireguard/wg*.conf; do
  process_interface $config_file
done
