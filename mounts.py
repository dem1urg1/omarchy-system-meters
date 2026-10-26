"""Capacity for mounted storage, grouping aliases sharing the same filesystem."""
import os
import re


VIRTUAL = {
    'proc', 'sysfs', 'tmpfs', 'devtmpfs', 'devpts', 'cgroup', 'cgroup2',
    'securityfs', 'pstore', 'bpf', 'debugfs', 'configfs', 'tracefs',
    'fusectl', 'mqueue', 'hugetlbfs', 'autofs', 'efivarfs', 'nsfs',
    'overlay', 'ramfs', 'rpc_pipefs', 'binfmt_misc', 'fuse.portal',
    'fuse.gvfsd-fuse',
}


def unescape(value):
    return re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), value)


def storage_rows(lines, statvfs=os.statvfs):
    groups = {}
    for line in lines:
        fields = line.split()
        try:
            separator = fields.index('-')
            filesystem = fields[separator + 1]
            if filesystem in VIRTUAL:
                continue
            mountpoint, device = unescape(fields[4]), unescape(fields[separator + 2])
            # A removed or inaccessible mount must not interrupt the other meters.
            capacity = statvfs(mountpoint)
            total = capacity.f_blocks * capacity.f_frsize
            used = (capacity.f_blocks - capacity.f_bfree) * capacity.f_frsize
            free = capacity.f_bavail * capacity.f_frsize
            if total <= 0 or used + free <= 0:
                continue
            key = (fields[2], filesystem, device)
            if key not in groups:
                groups[key] = dict(device=device, filesystem=filesystem, mounts=[],
                                   total=total, used=used, free=free,
                                   percent=100 * used / (used + free))
            if mountpoint not in groups[key]['mounts']:
                groups[key]['mounts'].append(mountpoint)
        except (ValueError, IndexError, OSError):
            continue
    rows = list(groups.values())
    for row in rows:
        row['mounts'].sort(key=lambda path: (path != '/', len(path), path))
    rows.sort(key=lambda row: ('/' not in row['mounts'], row['mounts'][0]))
    return rows


def mounted_disks():
    with open('/proc/self/mountinfo') as source:
        return storage_rows(source)
