#!/usr/bin/env python3
"""
Swift Storage Inspector

This script investigates OpenStack Swift storage to understand discrepancies
between reported storage usage and actual file sizes.

Features:
- Direct Swift API access for detailed inspection
- Compare rclone vs Swift API results
- Find hidden objects, versions, or metadata
- Calculate storage overhead and allocation differences
- Detailed object listing with sizes and metadata

Created: July 26, 2025
Target: SwissBackup OpenStack Swift storage
"""

import os
import sys
import json
import subprocess
import argparse
import re
from datetime import datetime
from typing import Dict, List, Optional, Tuple

try:
    from swiftclient import client as swift_client
    from swiftclient.exceptions import ClientException
except ImportError:
    print("ERROR: python3-swiftclient not installed")
    print("Install with: sudo apt install python3-swiftclient")
    sys.exit(1)


class SwiftInspector:
    def __init__(self):
        self.auth_config = {}
        self.swift_conn = None
        self.container_name = "mattermost-backups"
        
    def load_rclone_config(self) -> bool:
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
            
            # Map rclone config to Swift auth parameters
            self.auth_config = {
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
            
            print(f"✓ Loaded rclone config for user: {self.auth_config['user']}")
            print(f"✓ Auth URL: {self.auth_config['authurl']}")
            print(f"✓ Project: {self.auth_config['tenant_name']}")
            
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"ERROR: Failed to read rclone config: {e}")
            return False
        except Exception as e:
            print(f"ERROR: Failed to parse rclone config: {e}")
            return False
    
    def connect_swift(self) -> bool:
        """Establish connection to Swift API"""
        try:
            self.swift_conn = swift_client.Connection(**self.auth_config)
            
            # Test the connection
            account_info = self.swift_conn.head_account()
            print(f"✓ Connected to Swift API successfully")
            print(f"✓ Account containers: {account_info.get('x-account-container-count', 'unknown')}")
            print(f"✓ Account objects: {account_info.get('x-account-object-count', 'unknown')}")
            print(f"✓ Account bytes used: {account_info.get('x-account-bytes-used', 'unknown')}")
            
            return True
            
        except ClientException as e:
            print(f"ERROR: Swift API connection failed: {e}")
            return False
        except Exception as e:
            print(f"ERROR: Unexpected error connecting to Swift: {e}")
            return False
    
    def get_rclone_comparison(self) -> Dict:
        """Get rclone data for comparison"""
        print("\n" + "="*60)
        print("RCLONE COMPARISON DATA")
        print("="*60)
        
        rclone_data = {}
        remote = "swissbackup:mattermost-backups"
        
        try:
            # Get rclone about info
            result = subprocess.run(
                ['rclone', 'about', remote],
                capture_output=True, text=True, check=False
            )
            rclone_data['about'] = result.stdout.strip()
            print("Rclone 'about' output:")
            print(rclone_data['about'])
            
        except Exception as e:
            print(f"Failed to get rclone about: {e}")
        
        try:
            # Get rclone size info
            result = subprocess.run(
                ['rclone', 'size', remote],
                capture_output=True, text=True, check=False
            )
            rclone_data['size'] = result.stdout.strip()
            print("\nRclone 'size' output:")
            print(rclone_data['size'])
            
        except Exception as e:
            print(f"Failed to get rclone size: {e}")
        
        return rclone_data
    
    def analyze_container(self) -> Dict:
        """Analyze the container in detail"""
        print("\n" + "="*60)
        print("SWIFT CONTAINER ANALYSIS")
        print("="*60)
        
        try:
            # Get container info
            container_info = self.swift_conn.head_container(self.container_name)
            
            print(f"Container: {self.container_name}")
            print(f"Objects: {container_info.get('x-container-object-count', 'unknown')}")
            print(f"Bytes used: {container_info.get('x-container-bytes-used', 'unknown')}")
            print(f"Last modified: {container_info.get('last-modified', 'unknown')}")
            
            # Check for versioning
            if 'x-versions-location' in container_info:
                print(f"⚠ Versioning enabled, versions stored in: {container_info['x-versions-location']}")
            else:
                print("ℹ No versioning detected")
            
            return container_info
            
        except ClientException as e:
            print(f"ERROR: Failed to get container info: {e}")
            return {}
    
    def list_all_objects(self, show_details=False) -> List[Dict]:
        """List all objects in the container"""
        print("\n" + "="*60)
        print("ALL OBJECTS IN CONTAINER")
        print("="*60)
        
        all_objects = []
        marker = None
        total_size = 0
        
        try:
            while True:
                # Get objects in batches
                headers, objects = self.swift_conn.get_container(
                    self.container_name,
                    marker=marker,
                    limit=1000,
                    full_listing=True
                )
                
                if not objects:
                    break
                
                all_objects.extend(objects)
                marker = objects[-1]['name']
            
            print(f"Found {len(all_objects)} objects")
            
            if show_details:
                print("\nDetailed object listing:")
                print("-" * 80)
                print(f"{'Name':<40} {'Size':<12} {'Last Modified':<20} {'ETag':<32}")
                print("-" * 80)
                
                for obj in all_objects:
                    size_mb = obj['bytes'] / (1024 * 1024)
                    print(f"{obj['name']:<40} {size_mb:>8.2f} MB {obj['last_modified']:<20} {obj.get('hash', 'N/A'):<32}")
                    total_size += obj['bytes']
            else:
                # Just calculate total size
                total_size = sum(obj['bytes'] for obj in all_objects)
            
            total_mb = total_size / (1024 * 1024)
            total_gb = total_size / (1024 * 1024 * 1024)
            
            print(f"\nTotal calculated size: {total_size:,} bytes ({total_mb:.2f} MB / {total_gb:.2f} GB)")
            
            return all_objects
            
        except ClientException as e:
            print(f"ERROR: Failed to list objects: {e}")
            return []
    
    def analyze_backup_directories(self) -> Dict:
        """Analyze backup directories structure"""
        print("\n" + "="*60)
        print("BACKUP DIRECTORIES ANALYSIS")
        print("="*60)
        
        backup_analysis = {}
        
        try:
            # Get all objects
            headers, objects = self.swift_conn.get_container(
                self.container_name,
                full_listing=True
            )
            
            # Group by backup directory
            backup_dirs = {}
            for obj in objects:
                # Extract backup directory (first part of path)
                parts = obj['name'].split('/')
                if len(parts) >= 2 and re.match(r'^\d{8}_\d{6}$', parts[0]):
                    backup_dir = parts[0]
                    if backup_dir not in backup_dirs:
                        backup_dirs[backup_dir] = []
                    backup_dirs[backup_dir].append(obj)
            
            print(f"Found {len(backup_dirs)} backup directories:")
            
            for backup_dir, objects in backup_dirs.items():
                total_size = sum(obj['bytes'] for obj in objects)
                size_mb = total_size / (1024 * 1024)
                
                print(f"\n{backup_dir}:")
                print(f"  Objects: {len(objects)}")
                print(f"  Size: {size_mb:.2f} MB")
                print(f"  Files:")
                
                for obj in objects:
                    obj_size_mb = obj['bytes'] / (1024 * 1024)
                    print(f"    {obj['name']:<50} {obj_size_mb:>8.2f} MB")
                
                backup_analysis[backup_dir] = {
                    'objects': len(objects),
                    'total_size': total_size,
                    'files': objects
                }
            
            return backup_analysis
            
        except ClientException as e:
            print(f"ERROR: Failed to analyze backup directories: {e}")
            return {}
    
    def check_for_hidden_data(self):
        """Check for potential hidden data causing storage discrepancy"""
        print("\n" + "="*60)
        print("HIDDEN DATA INVESTIGATION")
        print("="*60)
        
        try:
            # Check account-level stats
            account_info = self.swift_conn.head_account()
            account_bytes = int(account_info.get('x-account-bytes-used', 0))
            
            # Get container-level stats
            container_info = self.swift_conn.head_container(self.container_name)
            container_bytes = int(container_info.get('x-container-bytes-used', 0))
            
            # Calculate object-level total
            headers, objects = self.swift_conn.get_container(self.container_name, full_listing=True)
            object_bytes = sum(obj['bytes'] for obj in objects)
            
            print(f"Account total bytes: {account_bytes:,} ({account_bytes / (1024**3):.3f} GB)")
            print(f"Container bytes: {container_bytes:,} ({container_bytes / (1024**3):.3f} GB)")
            print(f"Object sum bytes: {object_bytes:,} ({object_bytes / (1024**3):.3f} GB)")
            
            # Check for discrepancies
            container_vs_objects = container_bytes - object_bytes
            account_vs_container = account_bytes - container_bytes
            
            print(f"\nDiscrepancy analysis:")
            print(f"Container vs Objects: {container_vs_objects:,} bytes")
            print(f"Account vs Container: {account_vs_container:,} bytes")
            
            if container_vs_objects > 0:
                print(f"⚠ Container reports {container_vs_objects:,} more bytes than object sum")
                print("  This could indicate:")
                print("  - Object versioning or snapshots")
                print("  - Soft-deleted objects")
                print("  - Metadata overhead")
                print("  - Swift storage allocation overhead")
            
            if account_vs_container > 0:
                print(f"⚠ Account reports {account_vs_container:,} more bytes than this container")
                print("  This could indicate other containers or account metadata")
            
            # Check for other containers
            headers, containers = self.swift_conn.get_account()
            if len(containers) > 1:
                print(f"\n⚠ Found {len(containers)} containers in account:")
                for container in containers:
                    name = container['name']
                    size = container['bytes']
                    count = container['count']
                    print(f"  {name}: {count} objects, {size:,} bytes ({size / (1024**3):.3f} GB)")
            
        except Exception as e:
            print(f"ERROR during hidden data investigation: {e}")
    
    def run_full_investigation(self):
        """Run complete storage investigation"""
        print("SwiftBackup Storage Inspector")
        print("=" * 60)
        
        if not self.load_rclone_config():
            return False
        
        if not self.connect_swift():
            return False
        
        # Run all investigations
        rclone_data = self.get_rclone_comparison()
        container_info = self.analyze_container()
        all_objects = self.list_all_objects(show_details=True)
        backup_analysis = self.analyze_backup_directories()
        self.check_for_hidden_data()
        
        print("\n" + "="*60)
        print("INVESTIGATION SUMMARY")
        print("="*60)
        print("This investigation compared multiple data sources:")
        print("1. rclone 'about' and 'size' commands")
        print("2. Swift API container metadata")
        print("3. Swift API object listing and sizes")
        print("4. Account-level storage statistics")
        print("")
        print("Common causes of storage discrepancies:")
        print("- Object versioning keeping old versions")
        print("- Soft-deleted objects in trash/recycle")
        print("- Swift block allocation overhead")
        print("- Hidden metadata or system objects")
        print("- Provider-specific backup/snapshot features")
        
        return True


def main():
    parser = argparse.ArgumentParser(description='Investigate Swift storage discrepancies')
    parser.add_argument('--details', action='store_true', 
                       help='Show detailed object listings')
    parser.add_argument('--container', default='mattermost-backups',
                       help='Container name to investigate (default: mattermost-backups)')
    
    args = parser.parse_args()
    
    inspector = SwiftInspector()
    inspector.container_name = args.container
    
    try:
        success = inspector.run_full_investigation()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\nInvestigation interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
