#!/usr/bin/env python3
"""
Deep Swift Container Investigation

This script uses various Swift API parameters to find hidden or inaccessible objects
that might be causing storage discrepancies.
"""

import os
import sys
import subprocess
from swiftclient import client as swift_client
from swiftclient.exceptions import ClientException


def load_rclone_auth():
    """Load Swift credentials from rclone configuration"""
    try:
        result = subprocess.run(
            ['rclone', 'config', 'show', 'swissbackup'],
            capture_output=True, text=True, check=True
        )
        
        config_lines = result.stdout.strip().split('\n')
        config = {}
        
        for line in config_lines:
            if ' = ' in line:
                key, value = line.split(' = ', 1)
                config[key.strip()] = value.strip()
        
        auth_config = {
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
        
        return auth_config
        
    except Exception as e:
        print(f"ERROR: Failed to load rclone config: {e}")
        return None


def deep_container_scan(container_name='mattermost-backups'):
    """Perform deep scan of container with various parameters"""
    
    auth_config = load_rclone_auth()
    if not auth_config:
        return
    
    try:
        conn = swift_client.Connection(**auth_config)
        
        print("="*80)
        print("DEEP CONTAINER INVESTIGATION")
        print("="*80)
        
        # 1. Get container metadata first
        print("\n1. Container Metadata:")
        container_info = conn.head_container(container_name)
        for key, value in container_info.items():
            print(f"  {key}: {value}")
        
        print(f"\nContainer reports: {container_info.get('x-container-object-count', 'unknown')} objects")
        print(f"Container size: {container_info.get('x-container-bytes-used', 'unknown')} bytes")
        
        # 2. Try different listing parameters
        print("\n2. Different Listing Approaches:")
        
        # Standard listing
        print("\n  a) Standard listing (full_listing=True):")
        try:
            headers, objects = conn.get_container(container_name, full_listing=True)
            print(f"     Found {len(objects)} objects")
            total_size = sum(obj['bytes'] for obj in objects)
            print(f"     Total size: {total_size:,} bytes")
        except Exception as e:
            print(f"     ERROR: {e}")
        
        # Listing with different parameters
        print("\n  b) Listing with query parameters:")
        try:
            headers, objects = conn.get_container(
                container_name, 
                full_listing=True,
                query_string='format=json'
            )
            print(f"     Found {len(objects)} objects with format=json")
        except Exception as e:
            print(f"     ERROR: {e}")
        
        # Try to list with different prefixes to catch hidden objects
        print("\n  c) Listing with various prefixes:")
        prefixes_to_try = ['', '20', '.', '_', 'backup', 'old', 'tmp']
        
        for prefix in prefixes_to_try:
            try:
                headers, objects = conn.get_container(
                    container_name, 
                    prefix=prefix,
                    full_listing=True
                )
                if objects:
                    print(f"     Prefix '{prefix}': {len(objects)} objects")
                    for obj in objects[:3]:  # Show first 3
                        print(f"       {obj['name']}")
                    if len(objects) > 3:
                        print(f"       ... and {len(objects) - 3} more")
            except Exception as e:
                print(f"     Prefix '{prefix}' ERROR: {e}")
        
        # 3. Try to find deleted/versioned objects
        print("\n3. Checking for versioned or deleted objects:")
        
        # Check if there's a versions container
        try:
            headers, containers = conn.get_account()
            version_containers = [c for c in containers if 'version' in c['name'].lower() or c['name'].endswith('_versions')]
            if version_containers:
                print(f"   Found potential version containers: {[c['name'] for c in version_containers]}")
                for vc in version_containers:
                    try:
                        headers, objects = conn.get_container(vc['name'], full_listing=True)
                        print(f"   {vc['name']}: {len(objects)} objects, {vc['bytes']} bytes")
                    except Exception as e:
                        print(f"   {vc['name']}: ERROR {e}")
            else:
                print("   No version containers found")
        except Exception as e:
            print(f"   ERROR checking for version containers: {e}")
        
        # 4. Direct Swift CLI comparison
        print("\n4. Direct Swift CLI comparison:")
        
        # Set up environment
        env = os.environ.copy()
        env.update({
            'OS_AUTH_URL': auth_config['authurl'],
            'OS_USERNAME': auth_config['user'],
            'OS_PASSWORD': auth_config['key'],
            'OS_PROJECT_NAME': auth_config['tenant_name'],
            'OS_PROJECT_DOMAIN_NAME': auth_config['os_options']['project_domain_name'],
            'OS_USER_DOMAIN_NAME': auth_config['os_options']['user_domain_name'],
            'OS_REGION_NAME': auth_config['os_options']['region_name'],
            'OS_IDENTITY_API_VERSION': '3'
        })
        
        try:
            # Swift stat container
            result = subprocess.run(
                ['swift', 'stat', container_name],
                capture_output=True, text=True, env=env
            )
            print("   Swift stat output:")
            print("   " + "\n   ".join(result.stdout.strip().split('\n')))
            
            # Swift list with different options
            print("\n   Swift list --long:")
            result = subprocess.run(
                ['swift', 'list', container_name, '--long'],
                capture_output=True, text=True, env=env
            )
            lines = result.stdout.strip().split('\n')
            print(f"   Found {len([l for l in lines if l.strip()])} lines")
            for line in lines[:10]:  # Show first 10 lines
                if line.strip():
                    print(f"   {line}")
            if len(lines) > 10:
                print(f"   ... and {len(lines) - 10} more lines")
                
        except Exception as e:
            print(f"   Swift CLI ERROR: {e}")
        
        # 5. Summary of findings
        print("\n" + "="*80)
        print("SUMMARY OF FINDINGS")
        print("="*80)
        
        visible_objects = len(objects) if 'objects' in locals() else 0
        reported_objects = int(container_info.get('x-container-object-count', 0))
        
        print(f"Container metadata reports: {reported_objects} objects")
        print(f"Visible through API listing: {visible_objects} objects")
        print(f"Missing objects: {reported_objects - visible_objects}")
        
        if reported_objects > visible_objects:
            print("\nPossible explanations for missing objects:")
            print("- Objects in process of being deleted (Swift's eventual consistency)")
            print("- Objects with special permissions or access restrictions")
            print("- Corrupted object metadata")
            print("- SwissBackup provider-specific hidden objects or snapshots")
            print("- Objects created through different API versions")
            print("- Internal Swift system objects or manifests")
        
    except Exception as e:
        print(f"ERROR during investigation: {e}")


if __name__ == '__main__':
    deep_container_scan()
