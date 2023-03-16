#!/bin/bash

set -ex
DATADISK_MOUNTPOINT=/mnt/disks/pgsql
ROOT=${DATADISK_MOUNTPOINT}

DATADIR=${DATADISK_MOUNTPOINT}/data
LOGDIR=${DATADIR}/log
mkdir -p ${LOGDIR}
ARCHIVEDIR=${DATADIR}/pg_wal_archive
rm -rf ${ARCHIVEDIR}

# Remove old temp
PGTMP=${DATADIR}/base/pgsql_tmp
rm -rf "${PGTMP}"

chmod -R 750 /mnt/disks/pgsql/data/

echo "Starting Postgres..."
exec env /bin/postgres -D ${ROOT}/data -p 5432 -k ${ROOT} -h \*
