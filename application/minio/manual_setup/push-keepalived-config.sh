#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB1_PRIV=$(oxide instance nic list --project minio-poc --instance lb-1 | jq -r '.[] | .ip_stack.value.v4.ip')
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

echo "lb-1 private IP: $LB1_PRIV"
echo "lb-2 private IP: $LB2_PRIV"

# Detect the main NIC name on each LB (Ubuntu cloud-images vary)
LB1_IFACE=$(ssh ubuntu@$FIP "ip -br link | awk '/UP/ && !/lo/ {print \$1; exit}'")
LB2_IFACE=$(ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "ip -br link | awk '/UP/ && !/lo/ {print \$1; exit}'")
echo "lb-1 interface: $LB1_IFACE"
echo "lb-2 interface: $LB2_IFACE"

# Per-LB configs
cat > /tmp/keepalived-lb-1.conf <<EOF
global_defs {
    router_id LB1
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep -x haproxy"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_MINIO {
    state MASTER
    interface $LB1_IFACE
    virtual_router_id 51
    priority 110
    advert_int 1

    unicast_src_ip $LB1_PRIV
    unicast_peer {
        $LB2_PRIV
    }

    track_script {
        chk_haproxy
    }

    notify_master "/usr/local/bin/minio-fip-failover.sh"
}
EOF

cat > /tmp/keepalived-lb-2.conf <<EOF
global_defs {
    router_id LB2
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep -x haproxy"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_MINIO {
    state BACKUP
    interface $LB2_IFACE
    virtual_router_id 51
    priority 100
    advert_int 1

    unicast_src_ip $LB2_PRIV
    unicast_peer {
        $LB1_PRIV
    }

    track_script {
        chk_haproxy
    }

    notify_master "/usr/local/bin/minio-fip-failover.sh"
}
EOF

# Install + enable + start
echo ""
echo "=== lb-1 ==="
scp /tmp/keepalived-lb-1.conf ubuntu@$FIP:/tmp/keepalived.conf
ssh ubuntu@$FIP "sudo mkdir -p /etc/keepalived && sudo install -o root -g root -m 644 /tmp/keepalived.conf /etc/keepalived/keepalived.conf && rm /tmp/keepalived.conf && sudo systemctl enable --now keepalived && sleep 2 && sudo systemctl status keepalived --no-pager | head -12"

echo ""
echo "=== lb-2 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/keepalived-lb-2.conf ubuntu@$LB2_PRIV:/tmp/keepalived.conf
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo mkdir -p /etc/keepalived && sudo install -o root -g root -m 644 /tmp/keepalived.conf /etc/keepalived/keepalived.conf && rm /tmp/keepalived.conf && sudo systemctl enable --now keepalived && sleep 2 && sudo systemctl status keepalived --no-pager | head -12"

rm /tmp/keepalived-lb-1.conf /tmp/keepalived-lb-2.conf

echo ""
echo "=== Recent keepalived events on both nodes ==="
ssh ubuntu@$FIP "sudo journalctl -u keepalived --no-pager --since '30 seconds ago' | tail -10"
echo ""
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo journalctl -u keepalived --no-pager --since '30 seconds ago' | tail -10"