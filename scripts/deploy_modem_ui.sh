#!/bin/bash
PASS="di8Poonir@"
IP="192.168.8.1"

echo "Uploading files to router..."

# Upload Python backend
cat fibocom_modem.py | sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "cat > /usr/bin/fibocom_modem.py && chmod +x /usr/bin/fibocom_modem.py"

# Upload LuCI controller
sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "mkdir -p /usr/lib/lua/luci/controller"
cat fibocom.lua | sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "cat > /usr/lib/lua/luci/controller/fibocom.lua"

# Upload LuCI view
sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "mkdir -p /usr/lib/lua/luci/view"
cat fibocom_status.htm | sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "cat > /usr/lib/lua/luci/view/fibocom_status.htm"

# Clear LuCI cache
sshpass -p $PASS ssh -o StrictHostKeyChecking=no root@$IP "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache"

echo "Deployment complete! Please refresh your router web interface."
