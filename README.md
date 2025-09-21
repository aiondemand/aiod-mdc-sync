# Debezium MySQL PoC

## Overview

This proof of concept validates an architecture where two MySQL databases run on different virtual machines that share the same network. Debezium captures changes from the primary database and streams them through Kafka so that the secondary database keeps a synchronized copy.

- **Primary VM** – Hosts MySQL, Kafka, Kafka Connect (Debezium source) and the FastAPI app that writes into MySQL.
- **Secondary VM** – Hosts MySQL, a Kafka Connect JDBC sink, and a FastAPI app that reads from the synchronized database.

## Prerequisites

Prepare **two Linux VMs** (or physical servers) that can reach each other over the network.

Install on both machines:

- Docker Engine
- Docker Compose plugin (the `docker compose` subcommand)
- Git

> 💡 Use local/private IP addresses (for example `192.168.x.x`) when testing inside the same network. The primary VM's IP must be reachable from the secondary VM on ports `9093`, `8083`, and `3306`.

## 1. Clone the repository

Run on **each VM**:

```bash
git clone https://github.com/agimenobono/mysql-debezium-poc.git
cd mysql-debezium-poc/mysql-debezium-poc
```

The project folders of interest are now at `primary/`, `secondary/`, and `app/`. All subsequent commands assume you stay inside `mysql-debezium-poc/`.

## 2. Configure environment files

The services read configuration from `.env` files. Copy the provided examples and edit them with the same credentials on both machines.

### Primary VM

```bash
cd primary
cp .env.example .env
```

Edit `primary/.env` and set:

- `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` – Shared credentials that both VMs will use.
- `PRIMARY_PUB_IP` – The reachable IP or DNS name of the primary VM (use the private address if both machines are on the same LAN).

### Secondary VM

```bash
cd secondary
cp .env.example .env
```

Edit `secondary/.env` and set the same MySQL credentials as the primary. Configure `PRIMARY_PUB_IP` with the **primary VM's** reachable IP/DNS so the sink connector can contact Kafka.

Return to `mysql-debezium-poc/` when you finish editing on each VM.

## 3. Start the stack

Always start the primary side first so that Kafka and Debezium are ready before the sink connects.

### Primary VM

```bash
cd primary
docker compose up -d --build
```

Once the containers are running, **from the same directory** execute the verification script:

```bash
../../scripts/verify_setup.sh
```

The script checks Docker, the Compose plugin, the presence of the `.env` files, running containers (MySQL, Kafka, Kafka Connect), and the Kafka Connect REST API. Resolve any warnings before continuing.

Next, register the Debezium MySQL source connector using the helper script inside the primary stack:

```bash
./scripts/register_mysql_connector.sh
```

The script waits for the Connect REST endpoint, verifies the Debezium MySQL plugin, and then creates or updates the `mysql-source` connector with the defaults from your `.env`. Override any parameter (for example `CONNECT_URL`, `MYSQL_HOST`, or `TOPIC_PREFIX`) by exporting the corresponding environment variable before running the script.

Finally, validate the running Kafka Connect worker and connector directly from inside the container:

```bash
./scripts/check_debezium_connect.sh \
  --container db-connect \
  --connector-name mysql-source \
  --show-config \
  --validate-running
```

The validation script executes REST checks from inside the `db-connect` container, confirms the Debezium plugin is available, optionally validates the connector configuration, and reports a summary of pass/fail diagnostics. Add `--check-topics --kafka-container db-kafka` if you also want to confirm the internal Kafka topics.

### Secondary VM

After the primary stack is healthy, start the secondary services:

```bash
cd secondary
docker compose up -d --build
```

The sink connector image automatically registers itself with Kafka Connect running on the primary VM.

## 4. Smoke test the data flow

1. On the **primary VM**, create a sample item:
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"name": "demo", "description": "created on primary"}' \
     http://PRIMARY_VM_IP:8000/items
   ```

2. On the **secondary VM**, list synchronized items:
   ```bash
   curl http://SECONDARY_VM_IP:8001/items
   ```

You should see the item created on the primary VM. If not, review container logs with `docker compose logs` on each side.

## Repository structure

```
mysql-debezium-poc/
├─ app/                 # Shared FastAPI application (CRUD for items)
├─ primary/             # Debezium source stack (MySQL, Kafka, Kafka Connect, API)
│  └─ scripts/          # Helper scripts for managing the source connector
│     ├─ check_debezium_connect.sh
│     └─ register_mysql_connector.sh
├─ secondary/           # JDBC sink stack (MySQL, Kafka Connect sink, API)
└─ scripts/
   └─ verify_setup.sh   # Post-start verification script (run on the primary VM)
```

## Next steps

- Use the verification script whenever you restart the primary stack to quickly confirm dependencies and connectivity.
- Review `primary/debezium-source.json` and `secondary/jdbc-sink.json` if you need to adapt connector settings for additional tables or different topics.
