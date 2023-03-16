#!/bin/bash

# This script initializes the Database container of AlloyDB on-prem (SMURF).

set -ex

shopt -s nullglob

DATAPLANE_CONF_FILE=/conf/dataplane.conf
# Set dataplane environment variables
while ! [[ -s ${DATAPLANE_CONF_FILE} ]]; do
  echo "${DATAPLANE_CONF_FILE} is empty at $(date). Retrying after 1s"
  sleep 1
done
echo "${DATAPLANE_CONF_FILE} is not-empty at $(date). Proceeding."
cat ${DATAPLANE_CONF_FILE}
source ${DATAPLANE_CONF_FILE}

DATADISK_MOUNTPOINT=/mnt/disks/pgsql
# The marker file indicating a successful run of post start up script is
# intentionally persisted on the data disk to keep it agnostic to instance recreates/failovers.
MARKER_FILE_FOR_POST_STARTUP_SCRIPT=${DATADISK_MOUNTPOINT}/post_startup_success

DATADIR="${DATADISK_MOUNTPOINT}/data"
LOGDIR=${DATADIR}/log

if [[ ! -d "${DATADIR}" ]]; then
  echo "This is the first time running init...for AlloyDB..., proceeding to initdb."
  # InitDB
  /bin/initdb -D "${DATADIR}" -U alloydbadmin --encoding UTF8 --locale C.UTF-8 --auth-host trust --auth-local reject

  mkdir -p ${LOGDIR}

  # Flush all file system buffers to disk
  echo "Performing filesystem sync"
  /bin/sync
fi

echo "Successfully completed postgres initialization at $(date)"

# TODO(gbadamassi): Consider moving the post_startup script under a standalone systemctl service.
echo "Triggering the post-startup script asynchronously"
bash /smurf-scripts/alloydb_post_startup.sh ${MARKER_FILE_FOR_POST_STARTUP_SCRIPT} &

echo "Copying flag fragments..."
#cp -a -f ${SHARE_PG_CONF_D} ${DATADIR} #TODO revisit whether we want to copy additional conf files


cp -f /conf/pg_hba.conf ${DATADIR}
# Update WAL level to recover from incorrectly-restored volumes #TODO(gbadamassi) Is WAL recovery necessary for smurf?
LD_LIBRARY_PATH=/lib /utils/pg_control_editor --enforce_kernel_ipv6_support=false --pg_data_dir=${DATADIR}

# Start postgres
echo "Starting postgres!"

exec bash /smurf-scripts/alloydb_start_postgres.sh
