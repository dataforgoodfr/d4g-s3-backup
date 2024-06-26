# d4g-s3-backup

This repository is an attempt at creating a standard Docker image used to backup our various services files.

The result is a simple, fully configurable Docker image.

## Usage
Usage is documented in-script, to display the help menu use

```
$ docker run -it --rm ghcr.io/dataforgoodfr/d4g-s3-backup:latest --help
USAGE docker run -it --rm -v /var/data:/data -v /opt/backups:/backups ghcr.io/dataforgoodfr/d4g-s3-backup \
  [--access-key="<access_key>"] \
  [--secret-key="<secret_key>"] \
  [--backups-dir="/backups"] \
  [--bucket-name="backups"] \
  [--bucket-region="fr-par"] \
  [--data-dir="/data"] \
  [--host-base="%(bucket)s.s3.fr-par.scw.cloud"] \
  [--prom-metrics] \
  [--retention-days=30] \
  [--service-name="service"] \
  [--debug] \
  [--help]

Create backups for a specific dir easily and sync them to an s3 compatible bucket.

Data from <data_dir> will be backed up to <backups-dir>/<service-name>/<service-name>-2024-06-20.tar.gz
Files will be keps around for <retention-days> days.
Files will be synced to s3 under s3://<bucket-name>/<service-name> using supplied credentials and configuration.

Supported parameters :
-h, --help : display this message
--access-key : AWS-format access key (Required, also set by environment variable ACCESS_KEY)
--secret-key : AWS-format secret key (Required, also set by environment variable SECRET_KEY)
--backups-dir : backups root directory where will be stored (Optional, Default /opt/backups/, also set by environment variable BACKUPS_DIR)
--bucket-name : name of the bucket to sync backups to (Optional, Default backups, also set by environment variable BUCKET_NAME)
--bucket-region : S3 bucket region (Optional, Default fr-par, also set by environment variable BUCKET_REGION)
--data-dir : directory to backup (Optional, Default ./data, also set by environment variable DATA_DIR)
--host-base : S3 host base (Optional, Default %(bucket)s.s3.fr-par.scw.cloud, also set by environment variable HOST_BASE)
--host-bucket : Bucket host base (Optional, Default ${BUCKET_NAME}s.s3.fr-par.scw.cloud, also set by environment variable HOST_BUCKET)
--prom-metrics : enable prometheus metrics (Optional, Default false, also set by environment variable PROM_METRICS)
--prune : prune backups older than retention-days on remote s3 bucket (Optional, Default false, also set by environment variable PRUNE)
--retention-days : number of days to keep backups (Default 30, also set by environment variable RETENTION_DAYS)
--service-name : name of the service to backup (Optional, Default service, also set by environment variable SERVICE_NAME)
```

### Example
This one will create a backup for our private vaultwarden instance.

```
docker run -it --rm -v /opt/d4g-vaultwarden/data:/data \
  -v /opt/backups:/backups \
  ghcr.io/dataforgoodfr/d4g-s3-backup:latest \
  --access-key=<access-key> \
  --bucket-name=poletech-backups-s3 \
  --service-name=vaultwarden \
  --secret-key=<secret-key>
```
