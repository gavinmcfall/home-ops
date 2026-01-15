#!/bin/bash
# Migrate Pterodactyl database to Pelican
# Run this BEFORE deploying Pelican panel
#
# Prerequisites:
# 1. Create 1Password item "pelican" with:
#    - PELICAN_APP_KEY (copy from pterodactyl or generate new: base64:$(openssl rand -base64 32))
#    - PELICAN_MARIADB_PASSWORD (new secure password)
#    - MINIO_ACCESS_KEY (copy from pterodactyl)
#    - MINIO_SECRET_KEY (copy from pterodactyl)
# 2. Commit and push the mariadb changes first so the pelican user gets created

set -euo pipefail

echo "=== Pterodactyl to Pelican Database Migration ==="
echo ""

# Get MariaDB root password
echo "Fetching MariaDB root password..."
ROOT_PASSWORD=$(kubectl get secret mariadb-secret -n database -o jsonpath='{.data.mariadb-root-password}' | base64 -d)

if [ -z "$ROOT_PASSWORD" ]; then
    echo "ERROR: Could not retrieve MariaDB root password"
    exit 1
fi

# Get Pelican password (to verify 1Password item exists)
echo "Verifying pelican secret exists..."
PELICAN_PASSWORD=$(kubectl get secret mariadb-secret -n database -o jsonpath='{.data.PELICAN_MARIADB_PASSWORD}' 2>/dev/null | base64 -d || true)

if [ -z "$PELICAN_PASSWORD" ]; then
    echo "ERROR: PELICAN_MARIADB_PASSWORD not found in mariadb-secret"
    echo ""
    echo "Make sure you have:"
    echo "1. Created the 'pelican' item in 1Password with PELICAN_MARIADB_PASSWORD"
    echo "2. Committed and pushed the mariadb externalsecret changes"
    echo "3. Waited for the ExternalSecret to sync (check: kubectl get externalsecret -n database)"
    exit 1
fi

echo "✓ Pelican credentials found"
echo ""

# Check if pelican database already exists and has data
echo "Checking if pelican database already exists..."
PELICAN_EXISTS=$(kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'pelican';" 2>/dev/null || echo "0")

if [ "$PELICAN_EXISTS" = "1" ]; then
    TABLE_COUNT=$(kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'pelican';" 2>/dev/null || echo "0")
    if [ "$TABLE_COUNT" != "0" ]; then
        echo "WARNING: Pelican database already exists with $TABLE_COUNT tables!"
        read -p "Do you want to DROP and recreate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting migration"
            exit 1
        fi
        echo "Dropping existing pelican database..."
        kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -e "DROP DATABASE pelican;"
    fi
fi

# Create pelican database
echo "Creating pelican database..."
kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS pelican;"

# Create pelican user with password from secret
echo "Creating/updating pelican user..."
kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -e "
    CREATE USER IF NOT EXISTS 'pelican'@'%' IDENTIFIED BY '$PELICAN_PASSWORD';
    ALTER USER 'pelican'@'%' IDENTIFIED BY '$PELICAN_PASSWORD';
    GRANT ALL PRIVILEGES ON pelican.* TO 'pelican'@'%';
    FLUSH PRIVILEGES;
"

# Dump pterodactyl and import to pelican
echo ""
echo "Dumping pterodactyl database..."
kubectl exec -n database mariadb-0 -- mysqldump -u root -p"$ROOT_PASSWORD" --single-transaction pterodactyl > /tmp/pterodactyl-dump.sql

echo "Importing into pelican database..."
kubectl exec -i -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" pelican < /tmp/pterodactyl-dump.sql

# Verify
echo ""
echo "Verifying migration..."
PTERO_TABLES=$(kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'pterodactyl';")
PELICAN_TABLES=$(kubectl exec -n database mariadb-0 -- mysql -u root -p"$ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'pelican';")

echo "Pterodactyl tables: $PTERO_TABLES"
echo "Pelican tables:     $PELICAN_TABLES"

if [ "$PTERO_TABLES" = "$PELICAN_TABLES" ]; then
    echo ""
    echo "✓ Migration successful!"
    echo ""
    echo "Next steps:"
    echo "1. Commit and push the Pelican deployment changes"
    echo "2. Wait for Flux to deploy Pelican"
    echo "3. Visit https://pelican.\${SECRET_DOMAIN}"
    echo "4. Pelican will auto-upgrade the database schema"
    echo "5. Verify everything works"
    echo "6. Keep pterodactyl database for a few days as backup"
    echo "7. Once stable, you can drop pterodactyl: kubectl exec -n database mariadb-0 -- mysql -u root -p'...' -e 'DROP DATABASE pterodactyl;'"
else
    echo ""
    echo "WARNING: Table count mismatch! Please verify manually."
    exit 1
fi

# Cleanup
rm -f /tmp/pterodactyl-dump.sql
echo ""
echo "Done!"
