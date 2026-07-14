#!/usr/bin/env bash
# One-shot bootstrap: generates a CA + per-service certs on the shared
# `certs` volume, then sets built-in user passwords. Runs once and exits;
# the other services wait on it via `depends_on: condition: service_completed_successfully`.
set -eu

if [ ! -f config/certs/ca/ca.crt ]; then
  echo "Generating CA..."
  bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip
  unzip config/certs/ca.zip -d config/certs
fi

if [ ! -f config/certs/elasticsearch/elasticsearch.crt ]; then
  echo "Generating certs for elasticsearch, logstash, kibana, filebeat..."
  cat > config/certs/instances.yml <<EOF
instances:
  - name: elasticsearch
    dns: [elasticsearch, localhost]
  - name: logstash
    dns: [logstash, localhost]
  - name: kibana
    dns: [kibana, localhost]
  - name: filebeat
    dns: [filebeat, localhost]
EOF
  bin/elasticsearch-certutil cert --silent --pem \
    -out config/certs/certs.zip \
    --in config/certs/instances.yml \
    --ca-cert config/certs/ca/ca.crt \
    --ca-key config/certs/ca/ca.key
  unzip config/certs/certs.zip -d config/certs
fi

echo "Fixing permissions..."
chmod -R 644 config/certs/*/*.crt config/certs/ca/ca.crt
chmod -R 640 config/certs/*/*.key config/certs/ca/ca.key
find config/certs -type d -exec chmod 750 {} \;

echo "Waiting for Elasticsearch to be ready..."
until curl -s --cacert config/certs/ca/ca.crt https://elasticsearch:9200 | grep -q "missing authentication credentials"; do
  sleep 2
done

echo "Setting built-in user passwords..."
until curl -s -X POST --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  https://elasticsearch:9200/_security/user/kibana_system/_password \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do
  sleep 2
done
echo "  kibana_system password set."

curl -s -X POST --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  https://elasticsearch:9200/_security/user/logstash_internal_placeholder 2>/dev/null || true

# Create least-privilege service accounts for Logstash and Filebeat instead
# of using the elastic superuser.
curl -s -X POST --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  https://elasticsearch:9200/_security/user/logstash_internal \
  -d "{\"password\":\"${LOGSTASH_INTERNAL_PASSWORD}\",\"roles\":[\"logstash_writer\"],\"full_name\":\"Logstash internal user\"}" >/dev/null
echo "  logstash_internal user set."

curl -s -X POST --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  https://elasticsearch:9200/_security/user/filebeat_internal \
  -d "{\"password\":\"${FILEBEAT_INTERNAL_PASSWORD}\",\"roles\":[\"beats_admin\"],\"full_name\":\"Filebeat internal user\"}" >/dev/null
echo "  filebeat_internal user set."

echo "Bootstrap complete."
