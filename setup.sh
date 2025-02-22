#!/bin/bash

# iRacing AI Coach Setup Script
set -eo pipefail

REPO_URL="https://github.com/ChaosKyle/iracing-ai-coach"  # Update this
GRAFANA_PORT=3000
PYTHON_PORT=12345

# Check dependencies
check_deps() {
    command -v docker >/dev/null 2>&1 || { echo >&2 "Docker required - https://www.docker.com"; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Docker Compose required"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { echo >&2 "Python 3 required"; exit 1; }
    command -v git >/dev/null 2>&1 || { echo >&2 "Git required"; exit 1; }
}

# Create directory structure
create_structure() {
    echo "Creating project structure..."
    mkdir -p {alloy,scripts,dashboards,docs/blog}
    touch {README.md,ROADMAP.md,docker-compose.yml,alloy/config.river}
}

# Write base docker-compose.yml
write_docker_compose() {
    cat > docker-compose.yml <<EOF
version: '3'
services:
  grafana:
    image: grafana/grafana-oss:latest
    ports:
      - "$GRAFANA_PORT:3000"
    depends_on:
      - loki
      - mimir

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"

  mimir:
    image: grafana/mimir:latest
    command: -config.file=/etc/mimir/mimir.yaml
    ports:
      - "9009:9009"

  alloy:
    image: grafana/alloy:latest
    volumes:
      - ./alloy/config.river:/etc/alloy/config.river
    ports:
      - "12345:12345"

  pyroscope:
    image: pyroscope/pyroscope:latest
    ports:
      - "4040:4040"
EOF
}

# Write sample Alloy config
write_alloy_config() {
    cat > alloy/config.river <<EOF
prometheus.scrape "iracing_metrics" {
  targets = [
    { "__address__" = "host.docker.internal:$PYTHON_PORT" },
  ]
  forward_to = [prometheus.remote_write.mimir.receiver]
}

prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir:9009/api/v1/push"
  }
}
EOF
}

# Write sample Python collector
write_python_script() {
    cat > scripts/telemetry_collector.py <<EOF
from prometheus_client import start_http_server, Gauge
import irsdk
import time

ir = irsdk.IRSDK()
speed_gauge = Gauge('iracing_speed_mph', 'Current speed in MPH')
throttle_gauge = Gauge('iracing_throttle_pct', 'Throttle percentage')

def update_metrics():
    if ir.is_connected():
        speed_gauge.set(ir['Speed'])
        throttle_gauge.set(ir['Throttle'] * 100)

if __name__ == '__main__':
    start_http_server($PYTHON_PORT)
    print(f"Telemetry collector running on port {$PYTHON_PORT}")
    while True:
        ir.startup()
        update_metrics()
        time.sleep(0.1)
EOF
}

# Install Python requirements
install_python_deps() {
    echo "Installing Python dependencies..."
    python3 -m pip install prometheus-client irsdk-py
}

# Start services
start_services() {
    echo "Starting Docker services..."
    docker-compose up -d
}

# Main execution
main() {
    check_deps
    create_structure
    write_docker_compose
    write_alloy_config
    write_python_script
    install_python_deps
    start_services

    echo -e "\n✅ Setup complete!"
    echo -e "Access Grafana: http://localhost:$GRAFANA_PORT"
    echo -e "Run telemetry collector: python3 scripts/telemetry_collector.py"
}

main
