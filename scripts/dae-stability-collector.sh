#!/usr/bin/env bash
set -uo pipefail

OUT_DIR="${OUT_DIR:-/var/log/dae-stability}"
INTERVAL="${INTERVAL:-60}"
RUN_SECONDS="${RUN_SECONDS:-86400}"
CLIENT_IP="${CLIENT_IP:-192.168.0.66}"
IFACE="${IFACE:-ens160}"
PROBE_EVERY="${PROBE_EVERY:-300}"
JOURNAL_CURSOR_FILE="${OUT_DIR}/journal.cursor"

mkdir -p "$OUT_DIR"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${OUT_DIR}/${RUN_ID}"
mkdir -p "$RUN_DIR"
ln -sfn "$RUN_DIR" "${OUT_DIR}/latest"

METRICS="${RUN_DIR}/metrics.tsv"
EVENTS="${RUN_DIR}/events.log"
PROBES="${RUN_DIR}/probes.log"
ERRORS="${RUN_DIR}/errors.log"
DAED_LOG="${RUN_DIR}/daed-window.log"

log_event() {
  printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$EVENTS"
}

read_net() {
  local dev="$1"
  cat \
    "/sys/class/net/${dev}/statistics/rx_bytes" \
    "/sys/class/net/${dev}/statistics/tx_bytes" \
    "/sys/class/net/${dev}/statistics/rx_packets" \
    "/sys/class/net/${dev}/statistics/tx_packets" \
    "/sys/class/net/${dev}/statistics/rx_dropped" \
    "/sys/class/net/${dev}/statistics/tx_dropped" 2>/dev/null | paste -sd ' ' - || printf '0 0 0 0 0 0'
}

read_cpu() {
  awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11}' /proc/stat
}

sum_cpu_busy_pct() {
  local a="$1"
  local b="$2"
  python3 - "$a" "$b" <<'PY'
import sys
a=list(map(int, sys.argv[1].split()))
b=list(map(int, sys.argv[2].split()))
d=[b[i]-a[i] for i in range(min(len(a), len(b)))]
total=sum(d)
idle=(d[3] if len(d)>3 else 0) + (d[4] if len(d)>4 else 0)
print("0.0" if total <= 0 else f"{100*(total-idle)/total:.1f}")
PY
}

curl_probe() {
  local name="$1"
  local url="$2"
  local extra="${3:-}"
  local line
  line="$(curl -k -m 10 -o /dev/null -sS -w "remote=%{remote_ip} code=%{http_code} dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} total=%{time_total}" $extra "$url" 2>&1 || true)"
  printf '%s curl name=%s url=%s %s\n' "$(date -Is)" "$name" "$url" "$line" >> "$PROBES"
}

dns_probe() {
  local name="$1"
  local domain="$2"
  local line
  line="$(host -W 3 "$domain" 127.0.0.1 2>&1 | tr '\n' ';' | sed 's/[[:space:]]\+/ /g')"
  printf '%s dns name=%s domain=%s %s\n' "$(date -Is)" "$name" "$domain" "$line" >> "$PROBES"
}

collect_journal_window() {
  local since="$1"
  journalctl -u daed.service --since "@${since}" --no-pager > "$DAED_LOG" 2>/dev/null || true

  local direct proxy block reselect error warn client_lines
  direct="$(grep -c 'outbound=direct' "$DAED_LOG" 2>/dev/null || true)"
  proxy="$(grep -c 'outbound=proxy' "$DAED_LOG" 2>/dev/null || true)"
  block="$(grep -c 'outbound=block' "$DAED_LOG" 2>/dev/null || true)"
  reselect="$(grep -c 'Group re-selects dialer' "$DAED_LOG" 2>/dev/null || true)"
  error="$(grep -ciE 'level=error|panic|invalid|syntax|no-load|cannot have more than one node' "$DAED_LOG" 2>/dev/null || true)"
  warn="$(grep -ci 'level=warning' "$DAED_LOG" 2>/dev/null || true)"
  client_lines="$(grep -c "$CLIENT_IP" "$DAED_LOG" 2>/dev/null || true)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$direct" "$proxy" "$block" "$reselect" "$error" "$warn" "$client_lines" "$DAED_LOG"
}

snapshot_static() {
  {
    echo "run_id=${RUN_ID}"
    echo "start=$(date -Is)"
    echo "out=${RUN_DIR}"
    echo "interval=${INTERVAL}"
    echo "run_seconds=${RUN_SECONDS}"
    echo "client_ip=${CLIENT_IP}"
    echo "iface=${IFACE}"
    uname -a
    systemctl is-active daed.service paopaodns.service docker.service 2>/dev/null || true
  } > "${RUN_DIR}/meta.txt"

  {
    echo "===== ip addr ====="
    ip -br addr
    echo
    echo "===== ip route ====="
    ip route
    echo
    echo "===== sysctl ====="
    sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control net.ipv4.tcp_ecn net.ipv4.tcp_fastopen 2>/dev/null
    echo
    echo "===== listeners ====="
    ss -lntup | grep -E '(:53|:5301|:5302|:5304|:2023)[[:space:]]' || true
    ss -lnuup | grep -E '(:53|:5301|:5302|:5304)[[:space:]]' || true
    echo
    echo "===== daed config summary ====="
    python3 - <<'PY'
import sqlite3
con=sqlite3.connect('/etc/daed/wing.db')
for label, query in [
    ('global', 'select global from configs where selected=1'),
    ('dns', 'select dns from dns where selected=1'),
    ('routing', 'select routing from routings where selected=1'),
    ('groups', 'select id,name,policy,version from groups'),
]:
    print(f'--- {label} ---')
    for row in con.execute(query):
        print(row[0] if len(row)==1 else row)
PY
  } > "${RUN_DIR}/static.txt" 2>&1
}

write_header() {
  printf 'ts\tuptime_s\tcpu_busy_pct\trx_mbps\ttx_mbps\trx_drop_delta\ttx_drop_delta\test_total\test_client\tsyn_client\tudp_client\tdaed_active\tpaopaodns_active\tdirect\tproxy\tblock\treselect\terrors\twarnings\tclient_log_lines\tdaed_log\n' > "$METRICS"
}

main() {
  snapshot_static
  write_header
  log_event "collector started run_dir=${RUN_DIR}"

  local start_epoch now last_epoch next_probe
  start_epoch="$(date +%s)"
  last_epoch="$start_epoch"
  next_probe="$start_epoch"
  local net0 cpu0
  net0="$(read_net "$IFACE")"
  cpu0="$(read_cpu)"

  while true; do
    sleep "$INTERVAL"
    now="$(date +%s)"
    local elapsed=$((now - start_epoch))
    local span=$((now - last_epoch))
    [ "$span" -le 0 ] && span="$INTERVAL"

    local net1 cpu1 cpu_busy rx_b0 tx_b0 rx_p0 tx_p0 rx_d0 tx_d0 rx_b1 tx_b1 rx_p1 tx_p1 rx_d1 tx_d1
    net1="$(read_net "$IFACE")"
    cpu1="$(read_cpu)"
    cpu_busy="$(sum_cpu_busy_pct "$cpu0" "$cpu1")"
    read -r rx_b0 tx_b0 rx_p0 tx_p0 rx_d0 tx_d0 <<< "$net0"
    read -r rx_b1 tx_b1 rx_p1 tx_p1 rx_d1 tx_d1 <<< "$net1"

    local rx_mbps tx_mbps rx_drop_delta tx_drop_delta
    rx_mbps="$(python3 - <<PY
print(f"{(int('$rx_b1')-int('$rx_b0'))*8/int('$span')/1e6:.2f}")
PY
)"
    tx_mbps="$(python3 - <<PY
print(f"{(int('$tx_b1')-int('$tx_b0'))*8/int('$span')/1e6:.2f}")
PY
)"
    rx_drop_delta=$((rx_d1 - rx_d0))
    tx_drop_delta=$((tx_d1 - tx_d0))

    local est_total est_client syn_client udp_client daed_active paopaodns_active journal_stats
    est_total="$(ss -tan state established 2>/dev/null | tail -n +2 | wc -l)"
    est_client="$(ss -tan state established "( src ${CLIENT_IP} or dst ${CLIENT_IP} )" 2>/dev/null | tail -n +2 | wc -l)"
    syn_client="$(ss -tan state syn-sent "( src ${CLIENT_IP} or dst ${CLIENT_IP} )" 2>/dev/null | tail -n +2 | wc -l)"
    udp_client="$(ss -uan "( src ${CLIENT_IP} or dst ${CLIENT_IP} )" 2>/dev/null | tail -n +2 | wc -l)"
    daed_active="$(systemctl is-active daed.service 2>/dev/null || true)"
    paopaodns_active="$(systemctl is-active paopaodns.service 2>/dev/null || true)"
    journal_stats="$(collect_journal_window "$last_epoch")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -Is)" "$elapsed" "$cpu_busy" "$rx_mbps" "$tx_mbps" "$rx_drop_delta" "$tx_drop_delta" \
      "$est_total" "$est_client" "$syn_client" "$udp_client" "$daed_active" "$paopaodns_active" "$journal_stats" >> "$METRICS"

    if [ "$now" -ge "$next_probe" ]; then
      dns_probe baidu www.baidu.com
      dns_probe bilibili www.bilibili.com
      dns_probe google www.google.com
      curl_probe baidu https://www.baidu.com
      curl_probe google204 https://www.google.com/generate_204
      curl_probe ipinfo https://ipinfo.io/ip
      curl_probe ipip http://myip.ipip.net
      tc -s qdisc show dev "$IFACE" > "${RUN_DIR}/tc-${elapsed}.txt" 2>&1 || true
      next_probe=$((now + PROBE_EVERY))
    fi

    if [ "$daed_active" != "active" ] || [ "$paopaodns_active" != "active" ] || [ "${rx_drop_delta}" -gt 100 ] || echo "$journal_stats" | awk -F '\t' '{exit !($5 > 0)}'; then
      {
        echo "===== $(date -Is) anomaly ====="
        echo "daed=${daed_active} paopaodns=${paopaodns_active} rx_drop_delta=${rx_drop_delta}"
        echo "journal_stats=${journal_stats}"
        tail -80 "$DAED_LOG" 2>/dev/null || true
      } >> "$ERRORS"
    fi

    last_epoch="$now"
    net0="$net1"
    cpu0="$cpu1"

    [ "$elapsed" -ge "$RUN_SECONDS" ] && break
  done

  log_event "collector finished"
}

main "$@"
