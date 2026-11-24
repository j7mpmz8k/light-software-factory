#!/usr/bin/env bash
set -euo pipefail

create_isolated_db() {
  local role_name="$1"
  local db_name="$2"
  local role_pass="$3"

  echo "[factory-postgres] Provisioning isolated DB '${db_name}' for role '${role_name}'..."
  psql -v ON_ERROR_STOP=1 -v role_pass="$role_pass" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE ${role_name} WITH LOGIN PASSWORD :'role_pass' NOSUPERUSER NOCREATEDB NOCREATEROLE;
    ALTER ROLE ${role_name} SET statement_timeout = '30s';
    ALTER ROLE ${role_name} SET search_path TO public, extensions;
    CREATE DATABASE ${db_name} OWNER ${role_name};
    REVOKE ALL ON DATABASE ${db_name} FROM PUBLIC;
    GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${role_name};
EOSQL

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<-EOSQL
    CREATE SCHEMA IF NOT EXISTS extensions;
    GRANT USAGE ON SCHEMA extensions TO ${role_name};
    CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA extensions;
    ALTER SCHEMA public OWNER TO ${role_name};
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    GRANT ALL ON SCHEMA public TO ${role_name};
EOSQL
}

create_isolated_db "worker_agy"  "app_agy"  "${POSTGRES_AGY_PASSWORD:?POSTGRES_AGY_PASSWORD required}"
create_isolated_db "worker_qwen" "app_qwen" "${POSTGRES_QWEN_PASSWORD:?POSTGRES_QWEN_PASSWORD required}"
create_isolated_db "worker_glm"  "app_glm"  "${POSTGRES_GLM_PASSWORD:?POSTGRES_GLM_PASSWORD required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  REVOKE ALL ON DATABASE ${POSTGRES_DB} FROM PUBLIC;
EOSQL

echo "[factory-postgres] All 3 isolated worker databases ready (app_agy, app_qwen, app_glm)."
