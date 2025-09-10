# mysql-debezium-poc

This Proof of Concept (PoC) demonstrates MySQL-to-MySQL data synchronization using Debezium. The project is split into two parts:

- **primary/**: Run this on the PRIMARY VM. Hosts the source MySQL database and Debezium connector.
- **secondary/**: Run this on the SECONDARY VM. Hosts the target MySQL database and a JDBC sink connector.

## Quick Start

1. **Clone this repository on both PRIMARY and SECONDARY VMs:**
   ```bash
   git clone https://github.com/your-username/mysql-debezium-poc.git
   ```

2. **Configure environment variables:**
   fix: improve README documentation with detailed setup verification steps
   
   - Add network connectivity requirements
   - Include verification steps for Kafka Connect and Debezium
   - Add troubleshooting section for common issues
   - Clarify environment variables setup   - Copy `.env.example` to `.env` in both `primary/` and `secondary/`:
     ```bash
     cp primary/.env.example primary/.env
     cp secondary/.env.example secondary/.env
     ```
   - Edit both `.env` files and set these required values:
     - `PRIMARY_PUB_IP`: Public IP/DNS of PRIMARY VM
     - `MYSQL_ROOT_PASSWORD`: Choose a secure password
     - `MYSQL_DATABASE`: Name for your database
     - `MYSQL_USER`: Application database user
     - `MYSQL_PASSWORD`: Application user password

   Make sure both VMs can reach each other on the required ports (8000, 8083, 9093)

3. **Start services:**
   - On PRIMARY VM:
     ```bash
     cd primary && docker compose up --build
     ```
   - On SECONDARY VM:
     ```bash
     cd secondary && docker compose up --build
     ```

4. **Test synchronization:**
   - Insert data into PRIMARY using the FastAPI endpoint:
     ```bash
     curl -X POST -H "Content-Type: application/json" \
       -d '{"name": "item1", "description": "desc"}' \
       http://<PRIMARY_VM_IP>:8000/items
     ```
   - Verify data appears in SECONDARY:
     ```bash
     curl http://<SECONDARY_VM_IP>:8000/items
     ```

## Usage & Execution Order

1. **Pre-setup Verification:**
   ```bash
   # On both VMs: Check network and ports
   ./scripts/find_ips.sh
   ./scripts/check_ports.sh
   ```

2. **PRIMARY VM Setup:**
   - Start services in this order:
     ```bash
     cd primary
     docker compose up -d mysql    # Wait for MySQL to be ready
     docker compose up -d kafka zookeeper
     docker compose up -d kafka-connect
     docker compose up -d app
     ```
   - Verify PRIMARY setup:
     ```bash
     ./scripts/verify_setup.sh
     ```

3. **SECONDARY VM Setup:**
   - After PRIMARY is running, start secondary services:
     ```bash
     cd secondary
     docker compose up -d mysql
     docker compose up -d app
     ```

4. **Verify Connectivity:**
   ```bash
   # From SECONDARY VM, check connection to PRIMARY
   ./scripts/check_ports.sh <PRIMARY_VM_IP>
   curl http://<PRIMARY_VM_IP>:8083/connectors
   ```

5. **Start Data Synchronization:**
   - Wait for all services to be healthy (usually 1-2 minutes)
   - Check connector status as shown in Verify Setup section
   - Test with sample data using the provided API endpoints

Common workflow:
1. Data is inserted into PRIMARY MySQL via FastAPI
2. Debezium captures the changes
3. Changes flow through Kafka
4. JDBC Sink writes to SECONDARY MySQL
5. Data is available via SECONDARY FastAPI

## Directory Structure

## Helper Scripts

The `scripts/` directory contains helpful utilities for setup and troubleshooting:

- `check_ports.sh`: Check if required ports are available and accessible
- `find_ips.sh`: Display all network interfaces and IPs
- `verify_setup.sh`: Verify all components are properly configured

Usage:
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Check ports (optionally provide remote host IP)
./scripts/check_ports.sh [REMOTE_IP]

# Find IP addresses
./scripts/find_ips.sh

# Verify setup
./scripts/verify_setup.sh
```

## Directory Structure

```
mysql-debezium-poc/
├─ README.md
├─ scripts/
│  ├─ check_ports.sh
│  ├─ find_ips.sh
│  └─ verify_setup.sh
├─ primary/
│  ├─ .env.example
│  ├─ docker-compose.yml
│  ├─ init.sql
│  ├─ debezium-source.json
│  └─ app/
│      ├─ Dockerfile
│      ├─ requirements.txt
│      └─ main.py
└─ secondary/
   ├─ .env.example
   ├─ docker-compose.yml
   ├─ init.sql
   ├─ jdbc-sink.json
   └─ app/
       ├─ Dockerfile
       ├─ requirements.txt
       └─ main.py
```

## Exposed Ports

- **FastAPI**: `8000` (on both PRIMARY and SECONDARY)
- **MySQL**: `3306` (on both PRIMARY and SECONDARY)
- **Kafka Connect**: `8083`
- **Kafka**: `9092` (internal), `9093` (external)

## Requirements

- Docker Engine (docker.io on Ubuntu/Debian, docker-ce on CentOS/RHEL)
- Docker Compose Plugin (docker-compose-plugin)
- Python 3.8+
- Two VMs or servers with public IP addresses
- Network connectivity between VMs on ports:
  - 9093 (Kafka external)
  - 8083 (Kafka Connect)
  - 8000 (FastAPI)

## Verify Setup

After starting the services, verify the components are running correctly:

1. **Check Kafka Connect status:**
   ```bash
   curl http://<PRIMARY_VM_IP>:8083/connectors
   ```

2. **Verify Debezium connector:**
   ```bash
   # Check connector status
   curl http://<PRIMARY_VM_IP>:8083/connectors/mysql-connector/status
   
   # View connector configuration
   curl http://<PRIMARY_VM_IP>:8083/connectors/mysql-connector
   ```

3. **Verify JDBC Sink connector:**
   ```bash
   curl http://<PRIMARY_VM_IP>:8083/connectors/jdbc-sink/status
   ```

## Environment Variables

Key environment variables that need to be set in `.env` files:

- `PRIMARY_PUB_IP`: Public IP/DNS of the PRIMARY VM
- `MYSQL_ROOT_PASSWORD`: Root password for MySQL instances
- `MYSQL_DATABASE`: Database name for synchronization
- `MYSQL_USER`: MySQL user for the application
- `MYSQL_PASSWORD`: Password for the MySQL user

## Troubleshooting

- Ensure Docker Engine and Docker Compose plugin are installed:
  ```bash
  # Ubuntu/Debian
  sudo apt-get install -y docker.io docker-compose-plugin
  
  # CentOS/RHEL
  sudo dnf install -y docker-ce docker-compose-plugin
  ```
- Verify `.env` files are present and correctly configured
- Check network/firewall settings between VMs
- Use `docker compose logs` for debugging service startup issues
- Ensure all required ports are open between VMs

## Common Issues

1. **Connectors not appearing:**
   - Check if Kafka Connect is running: `docker compose logs kafka-connect`
   - Ensure all ports are accessible between VMs
   - Verify PRIMARY_PUB_IP is correct in both .env files

2. **Data not syncing:**
   - Check Debezium connector status
   - Verify MySQL replication user has correct permissions
   - Check JDBC sink connector logs

3. **Connection errors:**
   - Ensure firewalls allow traffic on required ports
   - Verify Docker network settings
   - Check DNS resolution between VMs

## Notes

- This PoC is for demonstration and testing purposes only
- Adjust configuration files as needed for your environment
- For production use, implement proper security measures
- Consider monitoring and error handling for real deployments 