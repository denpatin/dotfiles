#!/usr/bin/env bash
set -euo pipefail

PGDATA=/ram/pgdata
PGCONF=/etc/postgresql/pg-ram.conf
OWNER=denpatin

if [ -f "$PGDATA/PG_VERSION" ]; then
  exit 0
fi

if [ ! -d "$PGDATA" ]; then
  echo "pg-ram-init: $PGDATA does not exist (is /ram mounted?)" >&2
  exit 1
fi

initdb \
  --username=postgres \
  --encoding=UTF8 \
  --locale=C.UTF-8 \
  --auth-local=trust \
  --auth-host=trust \
  -D "$PGDATA"

if [ -f "$PGCONF" ]; then
  cat "$PGCONF" >>"$PGDATA/postgresql.conf"
fi

postgres --single -D "$PGDATA" postgres <<SQL
CREATE ROLE $OWNER SUPERUSER LOGIN CREATEDB;
SQL

echo "pg-ram-init: fresh ephemeral cluster at $PGDATA — port 5433, superusers: postgres, $OWNER"
