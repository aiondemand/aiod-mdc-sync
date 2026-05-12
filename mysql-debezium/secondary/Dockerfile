# Use the Confluent Connect base (or your current base)
FROM confluentinc/cp-kafka-connect:7.5.0

# Install the JDBC Sink connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.0

# Install Debezium MySQL connector for the unwrap transformation
ARG DEBEZIUM_VERSION=2.5.0.Final
RUN curl -fsSL https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/${DEBEZIUM_VERSION}/debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz | \
    tar -xz -C /usr/share/confluent-hub-components/

# Add MySQL JDBC driver (version can be updated later)
ARG MYSQL_JDBC_VERSION=8.3.0
RUN curl -fsSL -o /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/mysql-connector-j-${MYSQL_JDBC_VERSION}.jar \
    https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_JDBC_VERSION}/mysql-connector-j-${MYSQL_JDBC_VERSION}.jar
