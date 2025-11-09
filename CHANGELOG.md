# Changelog

## [v0.2.0] - 2025-11-10
### Added
- TLS-enabled Kafka listener and configuration so the secondary VM connects securely
  over the internet.
- Automation to generate broker/client certificates and a cross-VM replication check
  script that measures eventual consistency.
- Documentation updates covering firewall rules, TLS setup, and cross-VM validation
  workflow.

## [v0.1.0] - 2025-11-09
### Added
- Initial release of the Debezium MySQL proof of concept on the main branch.
- Documented the deployment architecture, environment configuration, and validation scripts for both primary and secondary stacks.
