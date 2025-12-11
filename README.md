# Debezium MySQL PoC

## Overview

This proof of concept demonstrates how Debezium and Kafka can replicate MySQL changes
from a primary virtual machine to a secondary virtual machine that is connected over
the public internet. Version 2 hardens the stack with TLS on the Kafka listener and
introduces an automated end-to-end check so you can measure eventual consistency
across the WAN link.

- **Primary VM** – Hosts MySQL, Kafka, Kafka Connect (Debezium source) and the
  FastAPI application that inserts data into MySQL.
- **Secondary VM** – Hosts MySQL, a Kafka Connect JDBC sink, and the FastAPI
  application that reads the replicated data.

## Prerequisites

Prepare **two Linux VMs** (or physical servers) that can reach each other over the
internet. Both machines need:

- Docker Engine
- Docker Compose plugin (the `docker compose` subcommand)
- Git
- OpenSSL (required for TLS assets)
- An outbound path on TCP/9093 from the secondary to the primary

> 🔐 Only expose TCP/9093 (Kafka over TLS) from the primary VM to the secondary
> VM's public IP. Kafka Connect (port 8083) and MySQL (3306) remain private to each
> host.

## 1. Clone the repository

Run on **each VM**:

```bash
git clone https://github.com/<your-org>/mysql-debezium-poc.git
cd mysql-debezium-poc/mysql-debezium-poc
```

You will work with the `primary/`, `secondary/`, and `app/` directories. All
instructions assume you remain inside `mysql-debezium-poc/`.

## 2. Configure environment files

Copy the provided examples and edit them with identical credentials on both
machines.

### Primary VM

```bash
cd primary
cp .env.example .env
```

Edit `primary/.env` and set:

- `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` – Shared
  MySQL credentials used by both stacks.
- `PRIMARY_PUB_IP` – The public DNS name or IP address that the secondary VM can
  reach.
- `KAFKA_SSL_PASSWORD` – Password that protects the generated Kafka keystore and
  truststore (store this securely).

### Secondary VM

```bash
cd secondary
cp .env.example .env
```

Edit `secondary/.env` and set:

- The same MySQL credentials you defined on the primary.
- `BOOTSTRAP_SERVERS` – `<PRIMARY_PUB_IP>:9093` using the value from the primary
  `.env` file.
- Optionally adjust the TLS truststore path/password if you copy the artifacts to a
  different location.

Return to `mysql-debezium-poc/` when you finish editing on each VM.

## 3. Generate Kafka TLS material (primary VM)

Run the helper to create a small certificate authority, broker certificate, and
client truststore. The script uses the variables from `primary/.env` by default.

Use PRIMARY_PUB_IP as the public domain, ej. kf-aiod-dev.iti.es

```bash
./scripts/generate_kafka_tls.sh kf-aiod-dev.iti.es
```

The artifacts are written to:

- `primary/secrets/` – Broker keystore, truststore, and CA certificate
- `secondary/secrets/` – Client truststore and CA certificate to copy to the
  secondary VM

Copy the contents of `secondary/secrets/` to the secondary VM (for example with
`scp`) and place them under `mysql-debezium-poc/secondary/secrets/`. Keep the
password from `KAFKA_SSL_PASSWORD` handy—it becomes
`CONNECT_SSL_TRUSTSTORE_PASSWORD` in `secondary/.env`.

## 4. Lock down network access

On the primary VM, restrict ingress so that only the secondary VM can reach
`TCP/9093`:

```bash
# Example using ufw
sudo ufw allow from <SECONDARY_PUBLIC_IP> to any port 9093 proto tcp
sudo ufw enable
```

All other Kafka ports remain internal to Docker. Confirm that the secondary VM can
reach the port via `openssl s_client -connect <PRIMARY_PUB_IP>:9093` (it should show
an established TLS session signed by the generated CA).

## 4.1 Check that public port is reachable from outside

Check that KAFKA_ADVERTISED_LISTENERS variable is using the current public port. In our POC, we made a redirection from 50010 to 9093 and the following parameter had to be changed: KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,SSL://${PRIMARY_PUB_IP}:9093 50010.

## 5. Start the primary stack

Always start the primary side first so Kafka and Debezium are ready before the sink
connects.

```bash
cd primary
docker compose up -d --build
```

Once containers are running, validate the setup in this order (still on the primary
VM):

1. `../../scripts/verify_setup.sh` – Confirms Docker/Compose, environment files,
   running containers, and the Kafka Connect REST API.
2. `./scripts/register_mysql_connector.sh` – Deploys the Debezium source connector.
3. `./scripts/check_debezium_connect.sh --container db-connect --connector-name mysql-source --show-config --validate-running`
   – Verifies the worker status. Add `--check-topics --kafka-container db-kafka`
   to confirm Kafka internal topics.

## 6. Start the secondary stack

After the primary stack is healthy, move to the secondary VM:

```bash
cd secondary
docker compose up -d --build
```

The sink connector container generates its own `connect-distributed.properties`
including TLS settings. Validate the stack with:

```bash
./scripts/check_sink_connector.sh --show-config
```

Add `--verbose` for raw connector status or `--timeout <seconds>` if the worker
needs longer to initialise.

## 7. Validate cross-VM eventual consistency

From either VM (the machine just needs network access to both APIs), run the helper
that creates a record on the primary API and waits for it to appear on the secondary
API:

```bash
./scripts/internet_consistency_check.sh \
  --primary http://<PRIMARY_PUB_IP>:8000 \
  --secondary http://<SECONDARY_PUBLIC_OR_PRIVATE_IP>:8001 \
  --timeout 180 --interval 5
```

The script reports how many seconds it took for the item to replicate. A failure
indicates connectivity or connector issues—check Docker logs on both VMs for more
information.

## Repository structure

```
mysql-debezium-poc/
├─ app/                 # Shared FastAPI application (CRUD for items)
├─ primary/             # Debezium source stack (MySQL, Kafka, Kafka Connect, API)
│  └─ scripts/          # Helper scripts for the source connector
├─ secondary/           # JDBC sink stack (MySQL, Kafka Connect sink, API)
│  └─ scripts/          # Health checks for the sink connector
└─ scripts/
   ├─ generate_kafka_tls.sh      # Generates TLS artifacts for Kafka/Connect
   ├─ internet_consistency_check.sh # Cross-VM replication smoke test
   └─ verify_setup.sh            # Primary-side environment validation
```

## Troubleshooting tips

- Use `docker compose logs -f <service>` to inspect individual container logs.
- `openssl s_client -connect <PRIMARY_PUB_IP>:9093` verifies the TLS certificate
  chain from outside Docker.
- `secondary/scripts/check_sink_connector.sh --verbose` shows connector errors if
  the sink cannot reach Kafka or MySQL.
- Rerun `scripts/generate_kafka_tls.sh --force` if you need to regenerate
  certificates (remember to copy the new truststore to the secondary VM).

## Next steps

- Extend the connector configurations in `primary/debezium-source.json` and
  `secondary/jdbc-sink.json` to cover more tables.
- Integrate additional monitoring or alerting for production scenarios.
