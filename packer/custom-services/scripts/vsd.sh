#!/bin/bash
set -eu

BASE="/opt/custom-services"

show_help() {
  echo -e "\033[1;36mVyOS Smart Daed (vsd) CLI\033[0m"
  echo "Usage: vsd <command>"
  echo ""
  echo "Commands:"
  echo "  update-geo    Update geosite.dat and geoip.dat from Loyalsoldier"
  echo "  update-daed   Update daed binary to the latest version and restart"
  echo "  optimize-nic  Auto-detect and apply NIC offloading and ring-buffer tuning"
  echo "  help          Show this help message"
  echo ""
}

update_geo() {
  echo -e "\033[1;32m[+] Triggering geo update...\033[0m"
  bash "${BASE}/scripts/geosite-update.sh"
}

update_daed() {
  echo -e "\033[1;32m[+] Triggering daed update...\033[0m"
  bash "${BASE}/scripts/update-daed.sh"
}

optimize_nic() {
  echo -e "\033[1;32m[+] Optimizing Network Interfaces (NIC)...\033[0m"
  
  # Find physical interfaces (e.g. eth0, enp3s0) that are UP
  INTERFACES=$(ip -o link show | awk -F': ' '$2 ~ /^(eth[0-9]+|en[a-zA-Z0-9]+)/ && $3 ~ /UP/ {print $2}')
  
  if [ -z "$INTERFACES" ]; then
    echo -e "\033[1;31m[-] No suitable physical interfaces found.\033[0m"
    return 1
  fi
  
  # Generate a temporary vbash script to safely configure VyOS
  TMP_SCRIPT=$(mktemp /tmp/vsd-optimize.XXXXXX.sh)
  
  cat << 'EOF' > "$TMP_SCRIPT"
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
EOF

  for IFACE in $INTERFACES; do
    echo "  - Configuring $IFACE..."
    cat << EOF >> "$TMP_SCRIPT"
set interfaces ethernet $IFACE offload gro
set interfaces ethernet $IFACE offload gso
set interfaces ethernet $IFACE offload hw-tc-offload
set interfaces ethernet $IFACE ring-buffer rx '4096'
set interfaces ethernet $IFACE ring-buffer tx '4096'
EOF
  done
  
  cat << 'EOF' >> "$TMP_SCRIPT"
commit
save
exit
EOF
  
  chmod +x "$TMP_SCRIPT"
  echo -e "\033[1;34m[*] Applying VyOS configurations...\033[0m"
  
  # Run the script and capture errors
  if ! "$TMP_SCRIPT" 2>&1 | grep -q "Set failed"; then
    echo -e "\033[1;32m[+] Optimization applied successfully!\033[0m"
  else
    echo -e "\033[1;33m[!] Some optimizations were rejected by your hardware driver.\033[0m"
    echo -e "\033[1;33m    This is normal for virtio/e1000 or unsupported NICs.\033[0m"
  fi
  
  rm -f "$TMP_SCRIPT"
}

case "${1:-help}" in
  update-geo)
    update_geo
    ;;
  update-daed)
    update_daed
    ;;
  optimize-nic)
    optimize_nic
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo -e "\033[1;31mUnknown command: $1\033[0m"
    show_help
    exit 1
    ;;
esac
