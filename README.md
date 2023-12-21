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
  [--bucket-name="backups"] \
  [--host-base="%(bucket)s.s3.fr-par.scw.cloud"] \
  [--data-dir="/data"] \
  [--backups-dir="/backups"] \
  [--service-name="service"] \
  [--retention-days=30] \
  [--bucket-region="fr-par"] \
  [--prom-metrics] \
  [--debug] \
  [--help]

Create backups for a specific dir easily and sync them to an s3 compatible bucket.
This script also supports publishing prometheu-compatible metrics through the Textfile Collector.

Data from <data_dir> will be backed up to <backups-dir>/<service-name>/<service-name>-2023-12-20.tar.gz
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
--host-bucket : Bucket host base (Optional, Default ${BUCKET_NAME}s.s3.fr-par.scw.cloud)
--host-base : S3 host base (Optional, Default %(bucket)s.s3.fr-par.scw.cloud)
--bucket-region : S3 bucket region (Optional, Default fr-par)
--retention-days : number of days to keep backups (Default 30)
--prom-metrics : enable prometheus metrics (Default false)
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
