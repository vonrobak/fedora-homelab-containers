# Storage Layout

## System Drive (128GB NVMe - BTRFS with subvolumes)
- /: Root filesystem (subvolume)
- /home: User data (subvolume)
- ~/containers/config: Service configs (small, fast access)
- ~/containers/docs: Documentation - naming scheme is all lower cap "YYYYMMDD-name-of-file.md"
- ~/containers/scripts: Automation scripts including dyndns-script
- ~/containers/quadlets symlink to ~/.config/containers/systemd: Quadlets
- ~/containers/secrets: secrets stored here with appropriate permission settings
- ~/containers/data
- ~/containers/cache symlink to /mnt/btrfs-pool/subvol6-tmp/container-cache

## Data Pool (10TB BTRFS - spinning hard drives with subvolumes)
Devices: 1x2TB + 2x4TB (expanding with +4TB soon)

### Subvolumes in /mnt/btrfs-pool/subvol*-namelistedbelow
1. docs         # Documents - intended for nextcloud
2. pics         # Photos - intended for nextcloud
3. opptak       # Phone Recordings - planned for Immich and Nextcloud
4. multimedia   # Media files (Jellyfin source) - **consider READ-ONLY for containers** - might be available for nextcloud
5. music        # Music files (Jellyfin source) - **consider READ-ONLY for containers** - might be available for nextcloud
6. tmp          # Temporary files / container cache
7. containers   # Container persistent data on storage pool

The first five subvolumes are shared as smb shares on the local network.

### Container Data Paths - # this needs to be revised as new services has been added
- Jellyfin config: ~/containers/config/jellyfin (SSD)
- Jellyfin cache: /mnt/btrfs-pool/subvol6-tmp/jellyfin (pool)
- Jellyfin media: /mnt/btrfs-pool/subvol4-multimedia (pool, ro)
- Nextcloud data: /mnt/btrfs-pool/subvol7-containers/nextcloud (pool)
- Database data: /mnt/btrfs-pool/subvol7-containers/databases (pool)

## Backup Strategy
- BTRFS read only snapshots → sent with btrfs send to 18TB External BTRFS drive on /run/media/patriark/WD-18TB/.snapshots
- Another 18TB drive clones the first backup drive once a year for off-site backups
- Currently all subvolumes on /, /home and within /mnt/btrfs-pool has been snapshotted and sent to external drive 1 and cloned to external drive 2 (last export 2025-10-23 for system drive - 2025-04-20 for btrfs pool)

## Capacity Planning
Current: ~9TB used of 10TB (90%)
Expansion: +4TB drive → 14TB total
Target: <80% usage after expansion

Expansion of SSD drives are also of interest. Most likely 2x 4TB Samsung SSDs.
