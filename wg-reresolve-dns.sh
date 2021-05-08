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

log () {
  echo "$1"
  logger -t "wg-reresolve-dns" "$1"
}

process_peer() {
  interface=$1
  pubkey=$2
  endpoint=$3
  if [[ -z $pubkey ]] || [[ -z $endpoint ]]; then
    return 1
  fi
  if [[ ! $(wg show "$interface" latest-handshakes) =~ ${pubkey//+/\\+} ]]; then
    return 1
  fi
  latest_handshake=$(wg show wg2 latest-handshakes | grep $pubkey | awk '{print $2}')
  if [[ $(($(date +%s) - $latest_handshake)) -lt 135 ]]; then
    return 0
  fi
  log "$interface: Re-resolving endpoint $endpoint for peer $pubkey"
  wg set "$interface" peer "$pubkey" endpoint "$endpoint"
}

process_interface() {
  config_file=$1
  interface="$(basename $config_file .conf)"
  log "$interface: Looking for peers that need a DNS reresolve"
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
