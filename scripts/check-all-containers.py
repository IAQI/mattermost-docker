#!/usr/bin/env python3
"""
Check all containers in the Swift account
"""

import subprocess
from swiftclient import client as swift_client


def load_rclone_auth():
    result = subprocess.run(['rclone', 'config', 'show', 'swissbackup'], capture_output=True, text=True, check=True)
    config_lines = result.stdout.strip().split('\n')
    config = {}
    
    for line in config_lines:
        if ' = ' in line:
            key, value = line.split(' = ', 1)
            config[key.strip()] = value.strip()
    
    return {
        'authurl': config.get('auth', ''),
        'user': config.get('user', ''),
        'key': config.get('key', ''),
        'tenant_name': config.get('tenant', ''),
        'auth_version': '3',
        'os_options': {
            'user_domain_name': config.get('domain', 'default'),
            'project_domain_name': config.get('tenant_domain', 'default'),
            'project_name': config.get('tenant', ''),
            'region_name': config.get('region', 'RegionOne')
        }
    }


def check_all_containers():
    auth_config = load_rclone_auth()
    conn = swift_client.Connection(**auth_config)
    
    print("="*80)
    print("ALL CONTAINERS IN SWIFT ACCOUNT")
    print("="*80)
    
    # Get account info
    account_info = conn.head_account()
    print(f"Account total containers: {account_info.get('x-account-container-count')}")
    print(f"Account total objects: {account_info.get('x-account-object-count')}")
    print(f"Account total bytes: {account_info.get('x-account-bytes-used')} ({int(account_info.get('x-account-bytes-used', 0)) / (1024**3):.3f} GB)")
    
    # List all containers
    headers, containers = conn.get_account()
    
    print(f"\nFound {len(containers)} containers:")
    print("-" * 80)
    
    total_account_size = 0
    
    for container in containers:
        name = container['name']
        count = container['count']
        size = container['bytes']
        size_gb = size / (1024**3)
        total_account_size += size
        
        print(f"\nContainer: {name}")
        print(f"  Objects: {count}")
        print(f"  Size: {size:,} bytes ({size_gb:.3f} GB)")
        
        # Get detailed info about each container
        try:
            container_info = conn.head_container(name)
            print(f"  Last modified: {container_info.get('last-modified', 'unknown')}")
            
            # List objects in each container
            if count > 0 and count <= 20:  # Only show details for small containers
                headers, objects = conn.get_container(name, limit=20)
                print(f"  Objects:")
                for obj in objects:
                    obj_size_mb = obj['bytes'] / (1024**2)
                    print(f"    {obj['name']:<50} {obj_size_mb:>8.2f} MB  {obj['last_modified']}")
            elif count > 20:
                headers, objects = conn.get_container(name, limit=5)
                print(f"  First 5 objects:")
                for obj in objects:
                    obj_size_mb = obj['bytes'] / (1024**2)
                    print(f"    {obj['name']:<50} {obj_size_mb:>8.2f} MB  {obj['last_modified']}")
                print(f"    ... and {count - 5} more objects")
                
        except Exception as e:
            print(f"  ERROR getting container details: {e}")
    
    print(f"\nCalculated total size: {total_account_size:,} bytes ({total_account_size / (1024**3):.3f} GB)")
    reported_size = int(account_info.get('x-account-bytes-used', 0))
    print(f"Account reported size: {reported_size:,} bytes ({reported_size / (1024**3):.3f} GB)")
    
    if abs(total_account_size - reported_size) > 1000:  # Allow small differences
        diff = reported_size - total_account_size
        print(f"⚠ Difference: {diff:,} bytes ({diff / (1024**3):.3f} GB)")
    else:
        print("✓ Sizes match!")


if __name__ == '__main__':
    check_all_containers()
