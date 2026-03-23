#!/usr/bin/env bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

usage() {
  cat <<EOF
USAGE docker run -it --rm -v /var/data:/data -v /opt/backups:/backups ghcr.io/dataforgoodfr/d4g-s3-backup /opt/restore.sh \\
  [--backups-dir="/backups"] \\
  [--service-name="service"] \\
  [--date="YYYY-MM-DD|latest"] \\
  [--restore-dir="/data"] \\
  [--from-s3] \\
  [--access-key="<access_key>"] \\
  [--secret-key="<secret_key>"] \\
  [--bucket-name="backups"] \\
  [--bucket-region="fr-par"] \\
  [--host-base="s3.fr-par.scw.cloud"] \\
  [--host-bucket="%(bucket)s.s3.fr-par.scw.cloud"] \\
  [--list-only] \\
  [--debug] \\
  [--help]

Restore backups from local storage or S3.

The script will:
1. Check for local backups in <backups-dir>/<service-name>/
2. If no local backups found (or --from-s3 specified), fetch from S3
3. Allow interactive date selection (using gum) or accept --date parameter
4. Move the existing target directory to a backup location (if writable)
5. Extract the backup to the target directory

If permissions prevent moving the target directory, the backup will be extracted
to <restore-dir>_restored and instructions provided for manual completion.

Supported parameters :
-h, --help : display this message
--backups-dir : local backups directory (Optional, Default /backups, also set by environment variable BACKUPS_DIR)
--service-name : name of the service to restore (Optional, Default app, also set by environment variable SERVICE_NAME)
--date : backup date to restore in YYYY-MM-DD format, or "latest" (Optional, interactive selection if not provided, also set by environment variable RESTORE_DATE)
--restore-dir : directory to restore to (Optional, Default /data, also set by environment variable RESTORE_DIR)
--from-s3 : force fetching from S3 even if local backups exist (Optional, Default false, also set by environment variable FROM_S3)
--list-only : list available backups and exit without restoring (Optional, Default false, also set by environment variable LIST_ONLY)
--debug : enable debug output (Optional, Default false, also set by environment variable DEBUG)

S3 parameters (only required when using --from-s3 or no local backups available):
--access-key : AWS-format access key (also set by environment variable ACCESS_KEY)
--secret-key : AWS-format secret key (also set by environment variable SECRET_KEY)
--bucket-name : name of the bucket to restore from (Optional, Default backups, also set by environment variable BUCKET_NAME)
--bucket-region : S3 bucket region (Optional, Default fr-par, also set by environment variable BUCKET_REGION)
--host-base : S3 host base (Optional, Default s3.fr-par.scw.cloud, also set by environment variable HOST_BASE)
--host-bucket : Bucket host base (Optional, Default %(bucket)s.s3.fr-par.scw.cloud, also set by environment variable HOST_BUCKET)
EOF
  exit 1
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  cleanup_temp_files
  if [ "$FAILURE" != 0 ]; then
    error "Restore for $SERVICE_NAME failed."
  fi
}

cleanup_temp_files() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
    debug "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    # shellcheck disable=SC2034
    NOCOLOR='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOCOLOR='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

info() {
  echo -e "${GREEN}$*${NOCOLOR}"
}

warn() {
  echo -e "${YELLOW}$*${NOCOLOR}"
}

error() {
  echo -e "${RED}$*${NOCOLOR}"
}

die() {
  error "$*"
  exit 1
}

debug() {
  if [ "$DEBUG" != "false" ]; then
    echo -e "$1"
  fi
}

check_gum() {
  if ! command -v gum &> /dev/null; then
    die "gum is required but not installed. Please run this inside the Docker container or install gum from https://github.com/charmbracelet/gum"
  fi
}

parse_params() {
  # Internal variables
  FAILURE=1
  USE_S3=false

  # Sane defaults
  DEBUG="${DEBUG:-false}"
  SERVICE_NAME="${SERVICE_NAME:-app}"
  BACKUPS_DIR="${BACKUPS_DIR:-/backups}"
  BUCKET_NAME="${BUCKET_NAME:-backups}"
  HOST_BASE="${HOST_BASE:-s3.fr-par.scw.cloud}"
  HOST_BUCKET="${HOST_BUCKET:-%(bucket)s.s3.fr-par.scw.cloud}"
  BUCKET_REGION="${BUCKET_REGION:-fr-par}"
  ACCESS_KEY="${ACCESS_KEY:-}"
  SECRET_KEY="${SECRET_KEY:-}"
  RESTORE_DATE="${RESTORE_DATE:-}"
  RESTORE_DIR="${RESTORE_DIR:-/data}"
  LIST_ONLY="${LIST_ONLY:-false}"
  FROM_S3="${FROM_S3:-false}"

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
    --date=*)
      RESTORE_DATE="${1#*=}"
      ;;
    --restore-dir=*)
      RESTORE_DIR="${1#*=}"
      ;;
    --list-only)
      LIST_ONLY="true"
      ;;
    --from-s3)
      FROM_S3="true"
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

  LOCAL_BACKUP_DIR="${BACKUPS_DIR}/${SERVICE_NAME}/"
  BUCKET_PATH="s3://${BUCKET_NAME}/${SERVICE_NAME}/"

  debug "Configuration"
  debug "BACKUPS_DIR: $BACKUPS_DIR"
  debug "LOCAL_BACKUP_DIR: $LOCAL_BACKUP_DIR"
  debug "SERVICE_NAME: $SERVICE_NAME"
  debug "RESTORE_DATE: ${RESTORE_DATE:-<interactive>}"
  debug "RESTORE_DIR: $RESTORE_DIR"
  debug "FROM_S3: $FROM_S3"
  debug "LIST_ONLY: $LIST_ONLY"

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

  debug "S3 configuration created"
}

list_available_backups() {
  debug "Listing backups in ${BUCKET_PATH}"

  local backups
  backups=$(/usr/bin/s3cmd --config=/.s3cfg ls "${BUCKET_PATH}" 2>/dev/null | awk '{print $4}' | grep -E "${SERVICE_NAME}-[0-9]{4}-[0-9]{2}-[0-9]{2}\.tar\.gz$" || true)

  if [ -z "$backups" ]; then
    die "No backups found for service '$SERVICE_NAME' in bucket '${BUCKET_NAME}'"
  fi

  # Extract dates and sort descending (newest first)
  AVAILABLE_DATES=()
  while IFS= read -r file_path; do
    if [ -n "$file_path" ]; then
      local filename
      filename=$(basename "$file_path")
      if [[ $filename =~ ${SERVICE_NAME}-([0-9]{4}-[0-9]{2}-[0-9]{2})\.tar\.gz$ ]]; then
        AVAILABLE_DATES+=("${BASH_REMATCH[1]}")
      fi
    fi
  done <<< "$backups"

  # Sort dates descending
  IFS=$'\n' AVAILABLE_DATES=($(sort -r <<< "${AVAILABLE_DATES[*]}")); unset IFS

  debug "Found ${#AVAILABLE_DATES[@]} backup(s)"
}

display_backups_list() {
  info "Available backups for service '$SERVICE_NAME':"
  echo ""
  local first=true
  for date in "${AVAILABLE_DATES[@]}"; do
    if [ "$first" = true ]; then
      echo "  $date (latest)"
      first=false
    else
      echo "  $date"
    fi
  done
  echo ""
}

select_backup_date() {
  if [ -n "$RESTORE_DATE" ]; then
    # Date provided via parameter
    if [ "$RESTORE_DATE" = "latest" ]; then
      SELECTED_DATE="${AVAILABLE_DATES[0]}"
      info "Using latest backup: $SELECTED_DATE"
    else
      # Validate the date exists
      local found=false
      for date in "${AVAILABLE_DATES[@]}"; do
        if [ "$date" = "$RESTORE_DATE" ]; then
          found=true
          break
        fi
      done

      if [ "$found" = false ]; then
        error "Backup for date '$RESTORE_DATE' not found."
        display_backups_list
        die "Please specify a valid date from the list above."
      fi

      SELECTED_DATE="$RESTORE_DATE"
      info "Using specified backup: $SELECTED_DATE"
    fi
  else
    # Interactive selection
    if [[ ! -t 0 ]]; then
      # Non-interactive mode, default to latest
      SELECTED_DATE="${AVAILABLE_DATES[0]}"
      warn "No TTY detected and no --date specified. Defaulting to latest backup: $SELECTED_DATE"
    else
      info "Select a backup to restore:"

      # Build menu options with (latest) marker
      local options=()
      local first=true
      for date in "${AVAILABLE_DATES[@]}"; do
        if [ "$first" = true ]; then
          options+=("$date (latest)")
          first=false
        else
          options+=("$date")
        fi
      done

      # Use gum for selection
      local selection
      selection=$(printf '%s\n' "${options[@]}" | gum choose --header "Available backups:")

      # Extract date from selection (remove " (latest)" suffix if present)
      SELECTED_DATE="${selection%% (latest)}"
      info "Selected backup: $SELECTED_DATE"
    fi
  fi
}

download_backup() {
  local backup_file="${SERVICE_NAME}-${SELECTED_DATE}.tar.gz"
  local s3_path="${BUCKET_PATH}${backup_file}"

  TEMP_DIR=$(mktemp -d -t "restore-${SERVICE_NAME}-XXXXXXXX")
  DOWNLOADED_FILE="${TEMP_DIR}/${backup_file}"

  info "Downloading backup from S3..."
  debug "Source: $s3_path"
  debug "Destination: $DOWNLOADED_FILE"

  if [[ -t 0 ]]; then
    # Interactive mode - show spinner
    gum spin --spinner dot --title "Downloading ${backup_file}..." -- \
      /usr/bin/s3cmd --config=/.s3cfg get "$s3_path" "$DOWNLOADED_FILE"
  else
    # Non-interactive mode
    /usr/bin/s3cmd --config=/.s3cfg get "$s3_path" "$DOWNLOADED_FILE"
  fi

  if [ ! -f "$DOWNLOADED_FILE" ]; then
    die "Failed to download backup file"
  fi

  info "Verifying backup integrity..."
  if ! tar -tzf "$DOWNLOADED_FILE" > /dev/null 2>&1; then
    die "Backup file is corrupted or invalid"
  fi

  info "Backup downloaded and verified successfully"
}

get_unique_backup_path() {
  local base_path="$1"
  local backup_path="${base_path}_bak"

  if [ ! -e "$backup_path" ]; then
    echo "$backup_path"
    return
  fi

  # Find unique timestamped path
  local today
  today=$(date +%Y-%m-%d)
  local counter=1

  while [ -e "${base_path}_bak_${today}_${counter}" ]; do
    ((counter++))
  done

  echo "${base_path}_bak_${today}_${counter}"
}

prepare_restore_directory() {
  RESTORE_TARGET="$RESTORE_DIR"
  PERMISSION_FALLBACK=false

  if [ -d "$RESTORE_DIR" ]; then
    info "Existing directory found at $RESTORE_DIR"

    # Check if we can move the directory (need write permission on parent)
    local parent_dir
    parent_dir=$(dirname "$RESTORE_DIR")

    if [ -w "$parent_dir" ]; then
      # We can move the directory
      local backup_path
      backup_path=$(get_unique_backup_path "$RESTORE_DIR")

      info "Moving existing directory to $backup_path"

      if [[ -t 0 ]]; then
        gum spin --spinner dot --title "Moving existing directory..." -- \
          mv "$RESTORE_DIR" "$backup_path"
      else
        mv "$RESTORE_DIR" "$backup_path"
      fi

      info "Existing directory moved to: $backup_path"
      BACKUP_LOCATION="$backup_path"
    else
      # Permission denied - use fallback
      warn "Cannot move existing directory (permission denied on parent directory)"
      warn "Will extract to alternate location instead"

      RESTORE_TARGET=$(get_unique_backup_path "$RESTORE_DIR" | sed 's/_bak/_restored/')
      # Handle the case where _restored path already exists
      if [ -e "$RESTORE_TARGET" ]; then
        local today
        today=$(date +%Y-%m-%d)
        local counter=1
        while [ -e "${RESTORE_DIR}_restored_${today}_${counter}" ]; do
          ((counter++))
        done
        RESTORE_TARGET="${RESTORE_DIR}_restored_${today}_${counter}"
      fi

      PERMISSION_FALLBACK=true
      warn "Backup will be extracted to: $RESTORE_TARGET"
    fi
  fi

  # Create target directory
  debug "Creating restore target directory: $RESTORE_TARGET"
  mkdir -p "$RESTORE_TARGET"
}

extract_backup() {
  info "Extracting backup to $RESTORE_TARGET..."

  if [[ -t 0 ]]; then
    gum spin --spinner dot --title "Extracting backup..." -- \
      tar -xzf "$DOWNLOADED_FILE" -C "$RESTORE_TARGET"
  else
    tar -xzf "$DOWNLOADED_FILE" -C "$RESTORE_TARGET"
  fi

  info "Backup extracted successfully"
}

print_summary() {
  echo ""
  info "=========================================="
  info "Restore completed successfully!"
  info "=========================================="
  echo ""
  echo "  Service:     $SERVICE_NAME"
  echo "  Date:        $SELECTED_DATE"
  echo "  Restored to: $RESTORE_TARGET"

  if [ -n "${BACKUP_LOCATION:-}" ]; then
    echo "  Original at: $BACKUP_LOCATION"
  fi

  echo ""

  if [ "$PERMISSION_FALLBACK" = true ]; then
    warn "=========================================="
    warn "MANUAL ACTION REQUIRED"
    warn "=========================================="
    echo ""
    warn "The backup was extracted to an alternate location because"
    warn "we lacked permission to move the original directory."
    echo ""
    echo "To complete the restore, run these commands with appropriate permissions:"
    echo ""
    echo "  rm -rf $RESTORE_DIR"
    echo "  mv $RESTORE_TARGET $RESTORE_DIR"
    echo ""
    # Exit with non-zero to indicate partial success
    FAILURE=2
  else
    FAILURE=0
  fi
}

# Main execution
setup_colors
check_gum
parse_params "$@"
create_s3_config

info "Fetching available backups..."
list_available_backups

if [ "$LIST_ONLY" = "true" ]; then
  display_backups_list
  FAILURE=0
  exit 0
fi

select_backup_date
download_backup
prepare_restore_directory
extract_backup
print_summary
