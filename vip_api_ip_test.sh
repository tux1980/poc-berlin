while true; do
  clear
  echo "=== OPENSHIFT VIP & BOOTSTRAP MONITORING ==="
  echo -n "API VIP (192.168.60.10):       "
  ping -c 1 -W 1 192.168.60.10 >/dev/null && echo "ONLINE (Ping OK)" || echo "OFFLINE"
  
  echo -n "Ignition Server (Port 22623):  "
  nc -zv -w 1 192.168.60.10 22623 2>&1 | grep -q "succeeded" && echo "ONLINE (Ready for Nodes)" || echo "OFFLINE"
  
  echo -n "Ingress VIP (192.168.60.20):   "
  ping -c 1 -W 1 192.168.60.20 >/dev/null && echo "ONLINE (Ping OK)" || echo "OFFLINE"
  
  echo "--------------------------------------------"
  sleep 3
done
