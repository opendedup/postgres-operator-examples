#!/bin/bash

set -ex

source "$(dirname "$0")/alloydb_util.sh"
MARKER_FILE_FOR_POST_STARTUP_SCRIPT="$1"
# Wait for ~ 30 minutes for postgres database to come up.
ATTEMPT=1
MAX_ATTEMPTS=1800
while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]
do
   set +e
   # Don't exit if this returns non-zero exit code
   psql -U alloydbadmin -h 127.0.0.1 -d postgres --command="SELECT 1;"
   exitcode=$?
   set -e
   if [[ $exitcode -eq 0 ]]; then
     break
   fi
   if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
     echo "Postgres server is not up after $ATTEMPT connection attempts. Exiting"
     exit 1
   fi
   echo "Postgres server not up. Sleeping for 1 second. Connection attempt $ATTEMPT/$MAX_ATTEMPTS"
   sleep 1
   ATTEMPT=$(( $ATTEMPT + 1 ))
done

echo "Postgres server is up, proceeding to create predefined AlloyDB users and databases."

alloydb::create_db_if_not_exists "CREATE DATABASE alloydbadmin;" postgres

# Make sure to change alloydbinternaluser() from
# src/backend/utils/misc/superuser.c whenever adding new users here.
alloydb::create_if_not_exists "CREATE USER alloydbsuperuser CREATEDB CREATEROLE INHERIT;" alloydbadmin
# We create the `<username>_table` in alloydbadmin db so that customers cannot drop
# these users (as they cannot drop these tables owned by these users).
alloydb::create_if_not_exists "CREATE USER alloydbagent CREATEDB CREATEROLE INHERIT IN ROLE alloydbsuperuser;" alloydbadmin
alloydb::create_if_not_exists "CREATE USER alloydbimportexport CREATEDB CREATEROLE INHERIT IN ROLE alloydbsuperuser;" alloydbadmin
alloydb::create_if_not_exists "CREATE USER alloydbreplica INHERIT REPLICATION;" alloydbadmin

# The following createuser for `postgres` races with the config-agent
# applying initial credentials. Do not fail the script execution, if
# the `postgres` user gets created first by the `config-agent`.
# See go/lux-cluster-creation-passwords for details.
alloydb::create_if_not_exists "CREATE ROLE postgres CREATEDB CREATEROLE INHERIT LOGIN IN ROLE alloydbsuperuser;" alloydbadmin

# TODO(gbadamassi) Create testuser for integration tests

/bin/psql -U alloydbadmin -h 127.0.0.1 -c "CREATE TABLE IF NOT EXISTS alloydbsuperuser_table(); ALTER TABLE alloydbsuperuser_table OWNER TO alloydbsuperuser;" alloydbadmin
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "CREATE TABLE IF NOT EXISTS alloydbagent_table(); ALTER TABLE alloydbagent_table OWNER TO alloydbagent;" alloydbadmin
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "CREATE TABLE IF NOT EXISTS alloydbreplica_table(); ALTER TABLE alloydbreplica_table OWNER TO alloydbreplica;" alloydbadmin
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "CREATE TABLE IF NOT EXISTS alloydbimportexport_table(); ALTER TABLE alloydbimportexport_table OWNER TO alloydbimportexport;" alloydbadmin

/bin/psql -U alloydbadmin -h 127.0.0.1 -c "ALTER DATABASE postgres OWNER TO alloydbsuperuser;" alloydbadmin
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "ALTER DATABASE template1 OWNER TO alloydbsuperuser;" alloydbadmin

# By default the public schema is owned by alloydbadmin and hence customers
# cannot drop it. This gives customers more flexibility with the public
# schema of all databases
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "ALTER SCHEMA public OWNER TO alloydbsuperuser;" postgres
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "ALTER SCHEMA public OWNER TO alloydbsuperuser;" template1

# Grant all default monitoring roles (pg_read_all_settings, pg_read_all_stats
# pg_stat_scan_tables) to alloydbsuperuser
/bin/psql -U alloydbadmin -h 127.0.0.1 -c "GRANT pg_monitor TO alloydbsuperuser;" postgres

# Grant invocation access to pg_replication_* functions to alloydbsuperuser.
for db in postgres template1
do
  cat << EOF | /bin/psql -U alloydbadmin -h 127.0.0.1 -d $db
GRANT EXECUTE ON FUNCTION pg_replication_origin_advance(text, pg_lsn) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_create(text) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_drop(text) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_oid(text) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_progress(text, boolean) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_is_setup() TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_progress(boolean) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_reset() TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_setup(text) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_xact_reset() TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_replication_origin_xact_setup(pg_lsn, timestamp with time zone) TO alloydbsuperuser;
GRANT EXECUTE ON FUNCTION pg_show_replication_origin_status() TO alloydbsuperuser;
EOF
done

SQLFILE=/config/init.sql
if test -f "$SQLFILE"; then
    echo "$SQLFILE exists - executing."
    /bin/psql -h localhost -U alloydbadmin -a -f {$SQLFILE}
fi

#Set Password
/bin/psql -h localhost -U alloydbadmin -c "ALTER USER alloydbadmin PASSWORD 'password'"

# Install pgsnap related extensions under alloydbadmin and hence customers cannot access it
# NOTE: Please remove the install here if the operation agent reinstalls the extension.
alloydb::create_if_not_exists "CREATE EXTENSION IF NOT EXISTS g_memory CASCADE;" alloydbadmin
alloydb::create_if_not_exists "CREATE EXTENSION IF NOT EXISTS google_job_scheduler CASCADE;" alloydbadmin #TODO(gbadamassi) determine if this extension is needed

echo "Successfully executed post startup script!"
touch "${MARKER_FILE_FOR_POST_STARTUP_SCRIPT:?marker file not defined}"
