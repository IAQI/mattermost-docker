# Maintenance Mode Implementation

## Overview

This implementation provides a user-friendly maintenance page during Mattermost backups instead of showing "Bad Gateway" errors. When a backup is running, users will see a professional maintenance page with automatic refresh functionality.

## How It Works

### Components

1. **Maintenance Page**: `/docker/nginx/conf.d/maintenance.html`
   - Beautiful, responsive maintenance page
   - Shows spinner animation for activity indication
   - Auto-refreshes every 30 seconds
   - Displays current time

2. **Nginx Configuration**: `/docker/nginx/conf.d/default.conf`
   - Checks for maintenance flag file `.maintenance`
   - Routes to maintenance page when flag exists
   - Normal operation when flag is absent

3. **Backup Script**: `/docker/scripts/backup-mattermost.sh`
   - Creates maintenance flag before stopping Mattermost
   - Removes flag after backup completion
   - Includes error handling to always clean up

4. **Test Script**: `/docker/scripts/test-maintenance.sh`
   - Manual testing of maintenance mode
   - Enable, disable, and check status

### Workflow During Backup

1. **Before Backup**: Script creates `.maintenance` flag file
2. **During Backup**: 
   - Nginx detects flag and shows maintenance page
   - Mattermost service is stopped (PostgreSQL continues running)
   - Backup operations proceed normally
3. **After Backup**: 
   - Mattermost service is restarted
   - Maintenance flag is removed
   - Normal service resumes

### User Experience

- **Before**: Users see "502 Bad Gateway" during backups
- **After**: Users see professional maintenance page with:
  - Clear explanation of what's happening
  - Estimated completion time
  - Spinning activity indicator
  - Automatic page refresh
  - Current time display
  - Professional branding

## Usage

### Automatic (Recommended)
Maintenance mode is automatically enabled/disabled during backups:
```bash
./backup-mattermost.sh --verbose
```

### Manual Testing
```bash
# Enable maintenance mode
./test-maintenance.sh enable

# Check status
./test-maintenance.sh status

# Disable maintenance mode
./test-maintenance.sh disable
```

## Technical Details

### Files Modified
- `docker-compose.nginx.yml`: Removed `:ro` from nginx config mount
- `nginx/conf.d/default.conf`: Added maintenance mode logic
- `scripts/backup-mattermost.sh`: Integrated maintenance mode
- `nginx/conf.d/maintenance.html`: Custom maintenance page

### Nginx Logic
```nginx
# Check if maintenance flag exists
if (-f /etc/nginx/conf.d/.maintenance) {
    return 503;
}

# Serve maintenance page for 503 errors
error_page 503 @maintenance;

location @maintenance {
    root /etc/nginx/conf.d;
    try_files /maintenance.html =503;
}
```

### Safety Features
- Maintenance flag is always removed on script exit (even on errors)
- Error handling ensures services are restarted if something fails
- Manual test script allows easy troubleshooting

## Benefits

1. **Better UX**: Professional maintenance page vs generic error
2. **User Communication**: Clear explanation of what's happening
3. **Reduced Support**: Users understand it's maintenance, not an issue
4. **Honest Feedback**: Spinner shows activity without false progress claims
5. **Professional Appearance**: Matches Mattermost branding
6. **Automatic Recovery**: Built-in error handling and cleanup

## Troubleshooting

### Maintenance Page Not Showing
```bash
# Check if flag file exists
ls -la /home/ubuntu/docker/nginx/conf.d/.maintenance

# Check nginx logs
sudo docker logs nginx_mattermost

# Test manually
./test-maintenance.sh enable
```

### Flag File Stuck
```bash
# Manually remove flag
rm -f /home/ubuntu/docker/nginx/conf.d/.maintenance
```

### Nginx Configuration Issues
```bash
# Test nginx config
sudo docker exec nginx_mattermost nginx -t

# Reload configuration
sudo docker exec nginx_mattermost nginx -s reload
```
