#!/bin/bash

# Mattermost Config Management Script
# Handles ownership changes for editing config.json

CONFIG_FILE="/home/ubuntu/docker/volumes/app/mattermost/config/config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    echo -e "${BLUE}Mattermost Config Manager${NC}"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  edit      - Change ownership to ubuntu user for editing"
    echo "  restore   - Restore ownership to container user (2000:2000)"
    echo "  status    - Show current file ownership"
    echo "  validate  - Validate JSON syntax"
    echo ""
    echo "Examples:"
    echo "  $0 edit     # Enable editing"
    echo "  $0 restore  # Restore after editing"
    echo "  $0 validate # Check JSON syntax"
}

check_file_exists() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
        exit 1
    fi
}

show_status() {
    echo -e "${BLUE}Config File Status${NC}"
    echo "==================="
    echo "File: $CONFIG_FILE"
    
    if [ -f "$CONFIG_FILE" ]; then
        ls -la "$CONFIG_FILE"
        
        # Check if file is owned by ubuntu user
        if [ "$(stat -c %U "$CONFIG_FILE")" = "ubuntu" ]; then
            echo -e "${GREEN}✓ File is editable by ubuntu user${NC}"
        else
            echo -e "${YELLOW}⚠ File is owned by container user - use 'edit' command to enable editing${NC}"
        fi
    else
        echo -e "${RED}✗ Config file not found${NC}"
    fi
}

enable_editing() {
    check_file_exists
    
    echo -e "${YELLOW}Enabling config editing...${NC}"
    echo "Changing ownership from container user to ubuntu user..."
    
    sudo chown ubuntu:ubuntu "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Config file is now editable${NC}"
        echo ""
        echo "Current status:"
        ls -la "$CONFIG_FILE"
        echo ""
        echo -e "${BLUE}You can now edit the file in VS Code or with:${NC}"
        echo "  nano $CONFIG_FILE"
        echo ""
        echo -e "${YELLOW}Remember to run '$0 restore' when done editing!${NC}"
    else
        echo -e "${RED}✗ Failed to change ownership${NC}"
        exit 1
    fi
}

restore_ownership() {
    check_file_exists
    
    echo -e "${YELLOW}Restoring config ownership...${NC}"
    echo "Changing ownership from ubuntu user to container user (2000:2000)..."
    
    sudo chown 2000:2000 "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Ownership restored successfully${NC}"
        echo ""
        echo "Current status:"
        ls -la "$CONFIG_FILE"
        echo ""
        echo -e "${BLUE}To apply config changes, restart Mattermost:${NC}"
        echo "  cd /home/ubuntu/docker"
        echo "  sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart mattermost"
    else
        echo -e "${RED}✗ Failed to restore ownership${NC}"
        exit 1
    fi
}

validate_json() {
    check_file_exists
    
    echo -e "${BLUE}Validating JSON syntax...${NC}"
    
    if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ JSON syntax is valid${NC}"
        
        # Show file size
        SIZE=$(stat -c%s "$CONFIG_FILE")
        echo "File size: ${SIZE} bytes"
        
        # Count some key sections
        echo ""
        echo "Configuration sections found:"
        grep -c '".*Settings"' "$CONFIG_FILE" | sed 's/^/  Settings sections: /'
        
    else
        echo -e "${RED}✗ JSON syntax errors found${NC}"
        echo ""
        echo "To see detailed error information:"
        echo "  python3 -m json.tool $CONFIG_FILE"
        exit 1
    fi
}

# Main execution
case "${1:-status}" in
    "edit")
        enable_editing
        ;;
    "restore")
        restore_ownership
        ;;
    "status")
        show_status
        ;;
    "validate")
        validate_json
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
