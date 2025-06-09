# geo-mysql-debezium-poc

This Proof of Concept (PoC) demonstrates MySQL-to-MySQL data synchronization using Debezium. The project is split into two parts:

- **primary/**: Run this on the PRIMARY VM. Hosts the source MySQL database and Debezium connector.
- **secondary/**: Run this on the SECONDARY VM. Hosts the target MySQL database and a JDBC sink connector.

## Quick Start

1. **Clone this repository on both PRIMARY and SECONDARY VMs.**
2. **Configure environment variables:**
   - Copy `.env.example` to `.env` in both `primary/` and `secondary/` and fill in the required values.
3. **Start services:**
   - On PRIMARY VM: `cd primary && docker-compose up --build`
   - On SECONDARY VM: `cd secondary && docker-compose up --build`
4. **Test synchronization:**
   - Use the provided `app/main.py` scripts to insert data into PRIMARY and verify it appears in SECONDARY.

## Directory Structure

```
geo-mysql-debezium-poc/
├─ README.md
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

## Requirements
- Docker & Docker Compose
- Python 3.8+

## Notes
- This PoC is for demonstration and testing purposes only.
- Adjust configuration files as needed for your environment. 