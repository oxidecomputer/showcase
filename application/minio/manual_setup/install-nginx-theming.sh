#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB1_PRIV=$(oxide instance nic list --project minio-poc --instance lb-1 | jq -r '.[] | .ip_stack.value.v4.ip')
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

# nginx site config: proxies MinIO Console, injects oxide-overrides.css
cat > /tmp/minio-console-proxy.conf <<'EOF'
upstream minio_console {
    server minio-inst-1:9001;
    server minio-inst-2:9001;
    server minio-inst-3:9001;
    server minio-inst-4:9001;
}

server {
    listen 127.0.0.1:8088;
    server_name _;

    # Disable gzip from upstream so sub_filter sees plain HTML
    proxy_set_header Accept-Encoding "";

    # Inject our stylesheet into every HTML response
    sub_filter '</head>' '<link rel="stylesheet" href="/oxide-overrides.css"></head>';
    sub_filter_once on;
    sub_filter_types text/html;

    # Inject our title-fixer script before </body>
    sub_filter_types *;
    sub_filter '</body>' '<script src="/oxide-tweaks.js"></script></body>';

    # Our static overrides
    location = /oxide-overrides.css {
        alias /etc/nginx/oxide-static/oxide-overrides.css;
        add_header Cache-Control "public, max-age=60";
    }
    location = /oxide-tweaks.js {
        alias /etc/nginx/oxide-static/oxide-tweaks.js;
        add_header Cache-Control "public, max-age=60";
    }

    # Everything else: reverse-proxy to MinIO Console
    location / {
        proxy_pass http://minio_console;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection upgrade;

        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 0;
    }
}
EOF

# Oxide-themed CSS overrides (first pass - we'll iterate)
cat > /tmp/oxide-overrides.css <<'EOF'
/* Oxide Object Storage - CSS overrides for MinIO Console */

:root {
  --oxide-bg-0: #080F11;
  --oxide-bg-1: #0B1416;
  --oxide-bg-2: #112125;
  --oxide-bg-3: #1F2E32;
  --oxide-fg-0: #E7E7E8;
  --oxide-fg-1: #989A9B;
  --oxide-accent: #48D597;
  --oxide-accent-hover: #57E0A1;
  --oxide-border: #1F2E32;
  --oxide-error: #FB6E88;
  --oxide-warning: #F5B944;
}

@import url('https://rsms.me/inter/inter.css');

html, body, #root {
  background-color: var(--oxide-bg-0) !important;
  color: var(--oxide-fg-0) !important;
  font-family: 'Inter', -apple-system, system-ui, sans-serif !important;
}

/* General surfaces */
div, section, header, nav, aside, main, footer {
  background-color: transparent;
}

/* Cards / panels */
[class*="MuiPaper"], [class*="Card"], [class*="card"] {
  background-color: var(--oxide-bg-1) !important;
  border-color: var(--oxide-border) !important;
  color: var(--oxide-fg-0) !important;
}

/* Sidebar / nav */
nav, [class*="sidebar"], [class*="Sidebar"], [class*="drawer"], [class*="Drawer"] {
  background-color: var(--oxide-bg-1) !important;
  border-right: 1px solid var(--oxide-border) !important;
}

/* Top bar / app bar */
[class*="AppBar"], [class*="appbar"], [class*="TopBar"], header[role="banner"] {
  background-color: var(--oxide-bg-1) !important;
  border-bottom: 1px solid var(--oxide-border) !important;
}

/* Tables */
table, thead, tbody, tr, th, td {
  background-color: transparent !important;
  border-color: var(--oxide-border) !important;
  color: var(--oxide-fg-0) !important;
}
thead, th {
  background-color: var(--oxide-bg-2) !important;
  color: var(--oxide-fg-1) !important;
  font-weight: 600 !important;
  letter-spacing: 0.02em;
}
tr:hover {
  background-color: var(--oxide-bg-2) !important;
}

/* Buttons - primary */
button[type="submit"],
button[class*="primary" i],
button[class*="Primary"],
[class*="MuiButton-containedPrimary"] {
  background-color: var(--oxide-accent) !important;
  color: var(--oxide-bg-0) !important;
  border: none !important;
  font-weight: 600 !important;
}
button[type="submit"]:hover,
button[class*="primary" i]:hover {
  background-color: var(--oxide-accent-hover) !important;
}

/* Buttons - secondary */
button {
  border-radius: 4px !important;
}
button:not([class*="primary" i]):not([type="submit"]) {
  background-color: var(--oxide-bg-2) !important;
  color: var(--oxide-fg-0) !important;
  border: 1px solid var(--oxide-border) !important;
}

/* Inputs */
input, textarea, select {
  background-color: var(--oxide-bg-2) !important;
  color: var(--oxide-fg-0) !important;
  border: 1px solid var(--oxide-border) !important;
  border-radius: 4px !important;
}
input:focus, textarea:focus, select:focus {
  border-color: var(--oxide-accent) !important;
  outline: none !important;
}

/* Links */
a, a:visited {
  color: var(--oxide-accent) !important;
}
a:hover {
  color: var(--oxide-accent-hover) !important;
}

/* Scrollbars (webkit) */
::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: var(--oxide-bg-0); }
::-webkit-scrollbar-thumb { background: var(--oxide-bg-3); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: var(--oxide-accent); }

/* Hide MinIO logo where we can find it */
img[alt*="MinIO" i],
img[src*="minio" i],
img[src*="MINIO" i],
svg[class*="logo" i] {
  display: none !important;
}

/* Inject Oxide brand text near top-left header */
header[role="banner"]::before,
[class*="AppBar"] ::before,
[class*="appbar"] ::before {
  content: "OXIDE OBJECT STORAGE";
  font-family: 'Inter', sans-serif;
  font-weight: 700;
  font-size: 14px;
  letter-spacing: 0.08em;
  color: var(--oxide-fg-0);
  padding-left: 16px;
}

/* Hide MinIO branding text strings via attribute selectors where possible */
[aria-label*="MinIO" i] { display: none !important; }
EOF

# Tiny JS to rewrite document.title from "MinIO ..." to "Oxide Object Storage"
cat > /tmp/oxide-tweaks.js <<'EOF'
(function () {
  function fixTitle() {
    if (document.title && document.title.indexOf('MinIO') !== -1) {
      document.title = 'Oxide Object Storage';
    }
  }
  fixTitle();
  // Watch for MinIO's React updating the title
  const obs = new MutationObserver(fixTitle);
  obs.observe(document.querySelector('title') || document.head, { childList: true, characterData: true, subtree: true });
})();
EOF

push_lb() {
  local TARGET=$1
  echo ""
  echo "=== $TARGET ==="

  scp -o ProxyJump=ubuntu@$INST1_IP /tmp/minio-console-proxy.conf /tmp/oxide-overrides.css /tmp/oxide-tweaks.js ubuntu@$TARGET:/tmp/

  ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$TARGET 'bash -se' <<'SHELL'
set -euo pipefail
# Install nginx if missing
if ! command -v nginx >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y nginx
fi

# Disable default site
sudo rm -f /etc/nginx/sites-enabled/default

# Install our site config and static assets
sudo install -o root -g root -m 644 /tmp/minio-console-proxy.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/minio-console-proxy.conf /etc/nginx/sites-enabled/

sudo mkdir -p /etc/nginx/oxide-static
sudo install -o root -g root -m 644 /tmp/oxide-overrides.css /etc/nginx/oxide-static/
sudo install -o root -g root -m 644 /tmp/oxide-tweaks.js /etc/nginx/oxide-static/

rm /tmp/minio-console-proxy.conf /tmp/oxide-overrides.css /tmp/oxide-tweaks.js

# Validate and reload
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
sudo ss -tlnp | grep ':8088'
SHELL
}

push_lb "$LB1_PRIV"
push_lb "$LB2_PRIV"

# Now switch HAProxy backend to point at local nginx
cat > /tmp/haproxy.cfg <<'EOF'
global
    daemon
    maxconn 4096
    log /dev/log local0
    log /dev/log local1 notice
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-bind-ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option forwardfor
    option http-server-close
    timeout connect 10s
    timeout client  5m
    timeout server  5m
    timeout http-request 30s
    timeout http-keep-alive 30s
    timeout queue 1m
    timeout tunnel 10m

listen stats
    bind 127.0.0.1:8404
    stats enable
    stats uri /
    stats refresh 5s

frontend minio_https
    bind :443 ssl crt /etc/haproxy/certs/minio-lb.pem alpn http/1.1
    default_backend minio_backend

backend minio_backend
    balance roundrobin
    option httpchk
    http-check send meth GET uri /minio/health/live ver HTTP/1.1 hdr Host minio.local
    http-check expect status 200
    default-server check inter 5s rise 2 fall 3 maxconn 1000
    server minio-inst-1 minio-inst-1:9000
    server minio-inst-2 minio-inst-2:9000
    server minio-inst-3 minio-inst-3:9000
    server minio-inst-4 minio-inst-4:9000

frontend minio_console_https
    bind :9443 ssl crt /etc/haproxy/certs/minio-lb.pem alpn http/1.1
    default_backend minio_console_backend

backend minio_console_backend
    balance roundrobin
    default-server check inter 5s rise 2 fall 3 maxconn 1000
    server local_nginx 127.0.0.1:8088
EOF

for LB in "$LB1_PRIV" "$LB2_PRIV"; do
  echo ""
  echo "=== Updating HAProxy on $LB ==="
  scp -o ProxyJump=ubuntu@$INST1_IP /tmp/haproxy.cfg ubuntu@$LB:/tmp/
  ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB "sudo install -o root -g root -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && rm /tmp/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"
done

rm /tmp/haproxy.cfg

echo ""
echo "=== Done. Reload https://$FIP:9443 in your browser (hard-refresh with Cmd+Shift+R to bust cache) ==="
echo "You should see MinIO Console styled in Oxide colors. CSS is in /etc/nginx/oxide-static/oxide-overrides.css on both LBs - iterate there."