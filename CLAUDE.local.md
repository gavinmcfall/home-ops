# Persistent Context (survives compaction)

## Pelican Panel Access

Pelican Panel runs in Kubernetes in the `games` namespace.

### Access Commands
```bash
# Exec into Pelican pod
kubectl exec -it -n games deploy/pelican -- bash

# List plugins
kubectl exec -n games deploy/pelican -- ls -la /pelican-data/plugins/

# View Laravel logs
kubectl exec -n games deploy/pelican -- tail -100 /pelican-data/storage/logs/laravel.log
```

### Plugin Cleanup (when import fails)
```bash
# Remove broken plugin files
kubectl exec -n games deploy/pelican -- rm -rf /pelican-data/plugins/server-documentation

# Clear cache
kubectl exec -n games deploy/pelican -- php artisan cache:clear
```

### Paths
- Plugin directory: `/pelican-data/plugins/`
- Logs: `/var/www/html/storage/logs/laravel.log`
- Web root: `/var/www/html/`

### Current Plugin Work
- Plugin source: `/tmp/pelican-plugins/server-documentation/`
- GitHub repo: `gavinmcfall/pelican-plugins`
- Current version: `v1.1.0-beta2`
