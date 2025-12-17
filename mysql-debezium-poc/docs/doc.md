# This document is an extension of the README with detailed test cases

## TLS connection test (#32) — ✅

Debezium supports TLS encryption for Kafka connections.

Deployed branch `main` with TLS enabled on https://kf-aiod-dev.iti.es (primary node).

Steps performed:

1. Run `generate_kafka_tls.sh` on the primary node using `PRIMARY_PUB_IP` as the server name (here `kf-aiod-dev.iti.es`).

2. In the primary `docker-compose` configuration, add these environment variables to the `db-kafka` service so the broker picks up TLS artifacts:

   - `KAFKA_SSL_KEYSTORE_FILENAME: kafka.server.keystore.p12`
   - `KAFKA_SSL_KEYSTORE_CREDENTIALS: kafka_keystore_creds`
   - `KAFKA_SSL_KEY_CREDENTIALS: kafka_key_creds`
   - `KAFKA_SSL_TRUSTSTORE_FILENAME: kafka.server.truststore.p12`
   - `KAFKA_SSL_TRUSTSTORE_CREDENTIALS: kafka_truststore_creds`

3. Copy the files from `secondary/secrets/` to the secondary VM (for example with `scp`) into `mysql-debezium-poc/secondary/secrets/`.

4. Ensure `KAFKA_ADVERTISED_LISTENERS` advertises the public address/port. In our POC we forwarded host port `50010` to container `9093`; the advertised listeners looked like:
   `PLAINTEXT://kafka:9092,SSL://${PRIMARY_PUB_IP}:9093`

## Delete rows (#34) — ✅

Deletes on supported tables work out of the box: change events are published to Kafka and consumed by the sink connector.

## Update rows (#34) — ✅

Updates on supported tables work out of the box: change events are published to Kafka and consumed by the sink connector.

## DDL changes (#34) — ✅

Schema/table changes (create/alter/drop) are handled when Debezium is configured to publish schema changes:

- `database.history.kafka.topic`: `schema-changes.DB_NAME`
- `include.schema.changes`: `true`

When a table is altered on the primary node, Debezium emits a schema-change event and the secondary will receive that change once the event is published.

Table selection is controlled by the connector property:

- `table.include.list`: `test_db.*`

Note: creating, dropping or renaming tables may require Debezium to create or update connector configuration; in some cases secondary nodes need a restart to pick up the new connector.

## Secondary failover and resynchronization (#34) — ✅

Test procedure:

1. Stop or disconnect the secondary node (simulate failover).
2. Continue writes (INSERT/UPDATE/DELETE) on the primary.
3. Restart the secondary node and the Kafka consumer.
4. Allow Debezium/Kafka to replay missed events.

Result: the secondary recovered missed events. By default Kafka uses `cleanup.policy=delete` and `retention.ms=604800000` (7 days).

Considerations:

- To retain compacted state instead of time-based deletion, set `cleanup.policy=compact` so the latest value per key is retained indefinitely (useful for long-term resynchronization).