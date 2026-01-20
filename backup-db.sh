#!/bin/bash

# Database backup script
set -e

echo "💾 Starting database backup..."

# Load environment variables
source /opt/xoleric/.env.production

# Create backup directory
BACKUP_DIR="/opt/xoleric/backup"
mkdir -p $BACKUP_DIR

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/xoleric_backup_$TIMESTAMP.sql"

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
docker exec xoleric-postgres pg_dump -U $DB_USER $DB_NAME > $BACKUP_FILE

# Compress backup
echo "Compressing backup..."
gzip $BACKUP_FILE

# Keep only last 7 days of backups
echo "Cleaning old backups..."
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

# Upload to cloud storage if configured
if [ ! -z "$BACKUP_BUCKET" ]; then
    echo "Uploading to cloud storage..."
    # Example for Google Cloud Storage
    # gsutil cp $BACKUP_FILE.gz $BACKUP_BUCKET/
    
    # Example for AWS S3
    # aws s3 cp $BACKUP_FILE.gz $BACKUP_BUCKET/
fi

# Backup uploads directory
echo "Backing up uploads..."
tar -czf $BACKUP_DIR/uploads_backup_$TIMESTAMP.tar.gz -C /opt/xoleric uploads

# Create backup report
cat > $BACKUP_DIR/backup_report_$TIMESTAMP.txt << EOF
Backup Report
=============
Date: $(date)
Backup Files:
- Database: $(basename $BACKUP_FILE.gz) ($(du -h $BACKUP_FILE.gz | cut -f1))
- Uploads: uploads_backup_$TIMESTAMP.tar.gz ($(du -h $BACKUP_DIR/uploads_backup_$TIMESTAMP.tar.gz | cut -f1))

Database Info:
- Name: $DB_NAME
- User: $DB_USER
- Size: $(docker exec xoleric-postgres psql -U $DB_USER -d $DB_NAME -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" | tail -3 | head -1)

System Info:
- Disk usage: $(df -h / | tail -1)
- Memory usage: $(free -h | awk '/Mem:/ {print $3 "/" $2}')
EOF

echo "✅ Backup completed: $BACKUP_FILE.gz"
