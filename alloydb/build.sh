docker pull gcr.io/alloydb-omni/pg-service:latest
cat <<EOF >Dockerfile
FROM gcr.io/alloydb-omni/pg-service:latest
USER 2345
COPY alloydb_init.sh /smurf-scripts/alloydb_init.sh
COPY alloydb_post_startup.sh /smurf-scripts/alloydb_post_startup.sh
COPY alloydb_start_postgres.sh /smurf-scripts/alloydb_start_postgres.sh
EOF
docker build . -t us-central1-docker.pkg.dev/spanner-repltest/alloydb/pgservice
docker push us-central1-docker.pkg.dev/spanner-repltest/alloydb/pgservice
rm -rf Dockerfile