#!/usr/bin/env bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

usage() {
  cat <<EOF
USAGE docker run -it --rm -v /var/data:/data -v /opt/backups:/backups ghcr.io/dataforgoodfr/d4g-s3-backup \\
  [--access-key="<access_key>"] \\
  [--secret-key="<secret_key>"] \\
  [--bucket-name="backups"] \\
  [--host-base="%(bucket)s.s3.fr-par.scw.cloud"] \\
  [--data-dir="/data"] \\
  [--backups-dir="/backups"] \\
  [--service-name="service"] \\
  [--retention-days=30] \\
  [--bucket-region="fr-par"] \\
  [--prom-metrics] \\
  [--debug] \\
  [--help]

Create backups for a specific dir easily and sync them to an s3 compatible bucket.
This script also supports publishing prometheu-compatible metrics through the Textfile Collector.

Data from <data_dir> will be backed up to <backups-dir>/<service-name>/<service-name>-$(date +%Y-%m-%d).tar.gz
Files will be keps around for <retention-days> days.
Files will be synced to s3 under s3://<bucket-name>/<service-name> using supplied credentials and configuration.

Supported parameters :
-h, --help : display this message
--debug : Print configuration before running (Optional)
--access-key : AWS access key (Required)
--secret-key : AWS secret key (Required)
--bucket-name : name of the bucket to sync backups to (Optional, Default backups)
--data-dir : directory to backup (Optional, Default ./data)
--service-name : name of the service to backup (Optional, Default service)
--backups-dir : backups root directory where will be stored (Optional, Default /opt/backups/)
--host-bucket : Bucket host base (Optional, Default \${BUCKET_NAME}s.s3.fr-par.scw.cloud)
--host-base : S3 host base (Optional, Default %(bucket)s.s3.fr-par.scw.cloud)
--bucket-region : S3 bucket region (Optional, Default fr-par)
--retention-days : number of days to keep backups (Default 30)
--prom-metrics : enable prometheus metrics (Default false)
EOF
  exit 1
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  if [ "$PROM_METRICS" == "true" ]; then
    write_metrics
  fi
  if [ "$FAILURE" != 0]; then
    error "Backup for $SERVICE_NAME $(date +%Y-%m-%d) failed."
  fi
  exit 0
}

function write_metrics() {
  # Write out metrics to a temporary file.
  END="$(date +%s)"
  # Last successful timestamp is now
  TIMESTAMP="$END"
  if [ "$FAILURE" != 0 ]; then
    TIMESTAMP="0"
  fi
  cat << EOF > "$TEXTFILE_COLLECTOR_DIR/${SERVICE_NAME}_backup.prom.$$"
# HELP ${SERVICE_NAME}_backup_duration Duration of the planned ${SERVICE_NAME} backup
# TYPE ${SERVICE_NAME}_backup_duration counter
${SERVICE_NAME}_backup_duration $((END - START))
# HELP ${SERVICE_NAME}_backup_failure Result of the planned ${SERVICE_NAME} backup
# TYPE ${SERVICE_NAME}_backup_failure gauge
${SERVICE_NAME}_backup_failure $FAILURE
# HELP ${SERVICE_NAME}_backup_last_time Timestamp of last successful backup
# TYPE ${SERVICE_NAME}_backup_last_time gauge
${SERVICE_NAME}_backup_last_time $TIMESTAMP
EOF

  # Rename the temporary file atomically.
  # This avoids the node exporter seeing half a file.
  mv "$TEXTFILE_COLLECTOR_DIR/${SERVICE_NAME}_backup.prom.$$" \
    "$TEXTFILE_COLLECTOR_DIR/${SERVICE_NAME}_backup.prom"
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    # shellcheck disable=SC2034
    NOCOLOR='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    echo "coucou"
    NOCOLOR='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

info() {
  echo -e "${GREEN}$*${NOCOLOR}"
}

error() {
  echo -e "${RED}$*${NOCOLOR}"
}

debug() {
  if [ "$DEBUG" == 'true' ]; then
    echo -e "$1"
  fi
}

parse_params() {
  if [ $# -gt 12 ]; then
    echo "Too many parameters provided"
    usage
  fi

  # Internal variables
  FAILURE=1
  START="$(date +%s)"

  # Sane defaults
  DEBUG="false"
  DATA_DIR="/data"
  SERVICE_NAME="app"
  BACKUPS_DIR="/backups"
  BUCKET_NAME="backups"
  HOST_BASE="s3.fr-par.scw.cloud"
  HOST_BUCKET="%(bucket)s.s3.fr-par.scw.cloud"
  BUCKET_REGION="fr-par"
  RETENTION_DAYS="30"
  PROM_METRICS="false"
  ACCESS_KEY=""
  SECRET_KEY=""

  while :; do
    case "${1-}" in
    -h | --help)
      usage
      ;;
    --debug)
      DEBUG="true"
      ;;
    --access-key=*)
      ACCESS_KEY="${1#*=}"
      ;;
    --secret-key=*)
      SECRET_KEY="${1#*=}"
      ;;
    --data-dir=*)
      DATA_DIR="${1#*=}"
      ;;
    --service-name=*)
      SERVICE_NAME="${1#*=}"
      ;;
    --backups-dir=*)
      BACKUPS_DIR="${1#*=}"
      ;;
    --bucket-name=*)
      BUCKET_NAME="${1#*=}"
      ;;
    --host-base=*)
      HOST_BASE="${1#*=}"
      ;;
    --host-bucket=*)
      HOST_BUCKET="${1#*=}"
      ;;
    --bucket-region=*)
      BUCKET_REGION="${1#*=}"
      ;;
    --retention-days=*)
      RETENTION_DAYS="${1#*=}"
      ;;
    --prom-metrics*)
      PROM_METRICS="true"
      ;;
    -?*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      break
      ;;
    esac
    shift
  done

  # Validate required parameters
  if [ -z "${ACCESS_KEY}" ]; then
    error "Missing required parameter: --access-key"
    usage
  fi

  if [ -z "${SECRET_KEY}" ]; then
    error "Missing required parameter: --secret-key"
    usage
  fi

  BACKUP_DIR="${BACKUPS_DIR}/${SERVICE_NAME}/"
  BACKUP_FILE="${BACKUP_DIR}${SERVICE_NAME}-$(date +%Y-%m-%d).tar.gz"
  BUCKET_PATH="s3://${BUCKET_NAME}/${SERVICE_NAME}/"

  return 0
}

create_s3_config() {
  echo "[default]" >> /.s3cfg
  echo "use_https = True" >> /.s3cfg
  echo "access_key = ${ACCESS_KEY}" >> /.s3cfg
  echo "secret_key = ${SECRET_KEY}" >> /.s3cfg
  echo "host_base = ${HOST_BASE}" >> /.s3cfg
  echo "host_bucket = ${HOST_BUCKET}" >> /.s3cfg
  echo "bucket_location = ${BUCKET_REGION}" >> /.s3cfg

  debug "S3 configuration :"
  debug "$(cat /.s3cfg)"
}

setup_colors
parse_params "$@"
create_s3_config

cd "$DATA_DIR"


# Create backup directory for service if it doesn't exist.
debug "Creating backups directory : ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Cleanup backups that are older than RETENTION_DAYS days
debug "Finding backups older than $RETENTION_DAYS in ${BACKUP_DIR}"
find "${BACKUP_DIR}" -type f -name "${SERVICE_NAME}-*.tar.gz" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;

debug "Compressing files to ${BACKUP_FILE}"
tar -czf "${BACKUP_FILE}" ./

debug "Uploading ${BACKUP_DIR} to ${BUCKET_PATH}"
/usr/bin/s3cmd --config=/.s3cfg sync "${BACKUP_DIR}" "${BUCKET_PATH}"
FAILURE=0

info "Backup for $SERVICE_NAME $(date +%Y-%m-%d) completed successfully."
if [ "$PROM_METRICS" == "true" ]; then
  write_metrics
fi
