# ELK Stack Docker Compose Template

A secured, self-hosted Elasticsearch + Logstash + Kibana + Filebeat stack.

## How the requirements are met

**Private network** — all five containers attach to a dedicated bridge
network, `elk-private`, defined once in `docker-compose.yml`. Services
resolve each other by name (`elasticsearch`, `logstash`, `kibana`) over
that network. Only Kibana's port is published to the host; Elasticsearch
and Logstash are unreachable from outside the Docker host unless you
deliberately uncomment their `ports:` blocks.

**Separate services** — Elasticsearch, Logstash, Kibana, Filebeat, and a
one-shot `setup` job each get their own service block, image, volumes,
and environment. Nothing is combined into a single container.

**Grouping** — common settings (network membership, restart policy,
logging driver, a shared `com.elk-stack.group: elk` label) are defined
once under the `x-elk-common` YAML anchor and merged into every service
with `<<: *elk-common`, so the group membership is declared in one place
instead of repeated five times.

## Layout

```
elk-stack/
├── docker-compose.yml
├── .env                        # versions, passwords, ports, memory limits
├── setup/                      # generates CA + certs, sets user passwords
│   ├── Dockerfile
│   └── entrypoint.sh
├── elasticsearch/config/elasticsearch.yml
├── logstash/
│   ├── config/logstash.yml
│   └── pipeline/logstash.conf
├── kibana/config/kibana.yml
└── filebeat/filebeat.yml
```

## Before first run

1. Edit `.env`:
   - Set real values for `ELASTIC_PASSWORD`, `KIBANA_PASSWORD`,
     `LOGSTASH_INTERNAL_PASSWORD`, `FILEBEAT_INTERNAL_PASSWORD`.
   - Generate `KIBANA_ENCRYPTION_KEY` with `openssl rand -hex 32`.
   - Adjust `STACK_VERSION` if you want a different Elastic release.
2. On Linux, raise the ES virtual memory limit on the host:
   ```
   sudo sysctl -w vm.max_map_count=262144
   ```

## Run

```bash
docker compose up -d --build
```

`setup` runs once, generates a CA and per-service TLS certs onto the
shared `certs` volume, waits for Elasticsearch, then creates the
`logstash_internal` and `filebeat_internal` service accounts. The other
services wait on `setup` (or on Elasticsearch's healthcheck) before
starting.

Kibana becomes available at `http://localhost:5601` (log in as `elastic`
with the password from `.env`).

## Notes / production hardening

- This is a single-node Elasticsearch cluster (`discovery.type:
  single-node`), suitable for dev/test. For production, run 3+ ES nodes
  and switch to `cluster.initial_master_nodes` / `discovery.seed_hosts`.
- Kibana is served over plain HTTP inside the private network; put a
  reverse proxy (nginx, Traefik) in front if exposing it beyond
  localhost, and terminate TLS there.
- Passwords in `.env` are placeholders — replace them, and keep `.env`
  out of version control (`git add .gitignore` with `.env` listed).
- To add more Filebeat/Logstash inputs, extend `filebeat/filebeat.yml`
  and `logstash/pipeline/logstash.conf` respectively.
