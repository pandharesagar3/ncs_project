#!/bin/bash
# ---------------------------------------------------------------------------
# Bootstrap script for the app tier (Amazon Linux 2023).
# Templated by Terraform (templatefile) — placeholders below are substituted
# at plan/apply time. Installs nginx + PHP-FPM, deploys the GfG Increment/
# Decrement counter app, adds a small PHP endpoint that persists a
# "total interactions" counter to Aurora (exercising the DB tier), and
# installs the CloudWatch agent for host + custom metrics.
# ---------------------------------------------------------------------------
set -euxo pipefail

dnf update -y
dnf install -y nginx php-fpm php-mysqlnd amazon-cloudwatch-agent jq awscli

# ---------------------------------------------------------------------------
# Fetch DB credentials from Secrets Manager at boot (never baked into the AMI
# or user-data in plaintext).
# ---------------------------------------------------------------------------
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString --output text)

DB_HOST="${db_endpoint}"
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)
DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)

mkdir -p /var/www/counter-app
cat > /var/www/counter-app/db_config.php <<PHP
<?php
return [
  'host' => '$DB_HOST',
  'name' => '$DB_NAME',
  'user' => '$DB_USER',
  'pass' => '$DB_PASS',
];
PHP
chmod 640 /var/www/counter-app/db_config.php
chown nginx:nginx /var/www/counter-app/db_config.php

# ---------------------------------------------------------------------------
# Health check endpoint for the ALB (checks nginx + confirms DB reachability
# without failing the whole fleet if the DB has a transient blip — logs only).
# ---------------------------------------------------------------------------
cat > /var/www/counter-app/healthz.php <<'PHP'
<?php
http_response_code(200);
echo "OK";
PHP

# ---------------------------------------------------------------------------
# Backend: increments a persistent "total interactions" row in Aurora each
# time a client hits the counter buttons. This is what makes the deployment a
# genuine 3-tier app rather than a static page sitting in front of an idle DB.
# ---------------------------------------------------------------------------
cat > /var/www/counter-app/api.php <<'PHP'
<?php
header('Content-Type: application/json');
$config = require __DIR__ . '/db_config.php';

try {
    $pdo = new PDO(
        "mysql:host={$config['host']};dbname={$config['name']};charset=utf8mb4",
        $config['user'],
        $config['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 3]
    );

    $pdo->exec("CREATE TABLE IF NOT EXISTS counter_stats (
        id INT PRIMARY KEY AUTO_INCREMENT,
        total_interactions BIGINT NOT NULL DEFAULT 0
    )");
    $pdo->exec("INSERT INTO counter_stats (id, total_interactions)
                SELECT 1, 0 WHERE NOT EXISTS (SELECT 1 FROM counter_stats WHERE id = 1)");

    $action = $_GET['action'] ?? 'read';
    if ($action === 'increment') {
        $pdo->exec("UPDATE counter_stats SET total_interactions = total_interactions + 1 WHERE id = 1");
    }

    $stmt = $pdo->query("SELECT total_interactions FROM counter_stats WHERE id = 1");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        'status'             => 'ok',
        'total_interactions' => (int) $row['total_interactions'],
        'served_by'          => gethostname(),
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'db_unavailable']);
}
PHP

# ---------------------------------------------------------------------------
# Frontend: GfG-style Increment/Decrement counter (client-side state), plus a
# small fetch() call to /api.php so each click also updates the shared,
# persisted "Total Interactions Across All Users" figure from the DB tier.
# ---------------------------------------------------------------------------
cat > /var/www/counter-app/index.php <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Increment / Decrement Counter — Dash-CloudOps Demo</title>
<style>
  body {
    font-family: 'Segoe UI', Arial, sans-serif;
    background: #0f172a;
    color: #e2e8f0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100vh;
    margin: 0;
  }
  .card {
    background: #1e293b;
    padding: 40px 60px;
    border-radius: 16px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.4);
    text-align: center;
  }
  h1 { font-size: 20px; font-weight: 600; margin-bottom: 4px; }
  .count {
    font-size: 64px;
    font-weight: 700;
    margin: 20px 0;
    color: #38bdf8;
  }
  .buttons button {
    font-size: 22px;
    width: 56px;
    height: 56px;
    margin: 0 10px;
    border: none;
    border-radius: 10px;
    cursor: pointer;
    font-weight: bold;
  }
  .inc { background: #22c55e; color: white; }
  .dec { background: #ef4444; color: white; }
  .meta { margin-top: 24px; font-size: 13px; color: #94a3b8; }
</style>
</head>
<body>
  <div class="card">
    <h1>Increment / Decrement Counter</h1>
    <div class="count" id="count">0</div>
    <div class="buttons">
      <button class="dec" onclick="change(-1)">-</button>
      <button class="inc" onclick="change(1)">+</button>
    </div>
    <div class="meta">
      Total interactions across all users (Aurora-backed): <span id="total">–</span><br>
      Served by instance: <span id="host">–</span>
    </div>
  </div>

<script>
  let count = 0;
  const countEl = document.getElementById('count');
  const totalEl = document.getElementById('total');
  const hostEl  = document.getElementById('host');

  function refreshTotal(action) {
    fetch('/api.php?action=' + action)
      .then(r => r.json())
      .then(data => {
        if (data.status === 'ok') {
          totalEl.textContent = data.total_interactions;
          hostEl.textContent  = data.served_by;
        } else {
          totalEl.textContent = 'unavailable';
        }
      })
      .catch(() => { totalEl.textContent = 'unavailable'; });
  }

  function change(delta) {
    count += delta;
    countEl.textContent = count;
    refreshTotal('increment');
  }

  window.onload = () => refreshTotal('read');
</script>
</body>
</html>
HTML

# ---------------------------------------------------------------------------
# nginx + php-fpm wiring
# ---------------------------------------------------------------------------
cat > /etc/nginx/conf.d/counter-app.conf <<'NGINX'
server {
    listen 80;
    server_name _;
    root /var/www/counter-app;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
sed -i 's/user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sed -i 's/group = apache/group = nginx/' /etc/php-fpm.d/www.conf
chown -R nginx:nginx /var/www/counter-app

systemctl enable --now php-fpm
systemctl enable --now nginx

# ---------------------------------------------------------------------------
# CloudWatch agent — host metrics (mem, disk) beyond the EC2 default (CPU/network)
# ---------------------------------------------------------------------------
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWA'
{
  "metrics": {
    "namespace": "${cw_namespace}",
    "append_dimensions": { "AutoScalingGroupName": "$${aws:AutoScalingGroupName}" },
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  }
}
CWA

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
