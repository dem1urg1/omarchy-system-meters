#!/usr/bin/python3
"""Stream system usage without counting reclaimable cache as used RAM."""
import json
import os
import re
import time
from mounts import mounted_disks


def cpu_times():
    times = {}
    with open('/proc/stat') as source:
        for line in source:
            parts = line.split()
            if not parts or not re.fullmatch(r'cpu\d*', parts[0]):
                break
            fields = [int(value) for value in parts[1:9]]
            times[parts[0]] = (sum(fields), fields[3] + fields[4])
    return times


def cpu_usage(previous, current):
    elapsed = current[0] - previous[0]
    usage = 100 * (1 - (current[1] - previous[1]) / elapsed) if elapsed > 0 else 0
    return max(0, min(100, usage))


def swap_backends():
    try:
        with open('/proc/swaps') as source:
            devices = [line.split()[0] for line in list(source)[1:] if line.split()]
    except OSError:
        return []
    has_zram = any(os.path.basename(device).startswith('zram') for device in devices)
    has_disk = any(not os.path.basename(device).startswith('zram') for device in devices)
    return (['zram'] if has_zram else []) + (['disk'] if has_disk else [])


with open('/proc/cpuinfo') as source:
    cpu_model = next((line.split(':', 1)[1].strip() for line in source
                      if line.startswith('model name')), 'Processor')
disk_filesystem, disk_device = '', '/'
with open('/proc/self/mountinfo') as source:
    for line in source:
        fields = line.split()
        if fields[4] == '/':
            separator = fields.index('-')
            disk_filesystem, disk_device = fields[separator + 1:separator + 3]
            break

# udev caches SMBIOS memory device sizes, readable without administrator access.
try:
    with open('/run/udev/data/+dmi:id') as source:
        memory_devices = source.read()
    installed_ram = sum(int(size) for size in re.findall(r'^E:MEMORY_DEVICE_\d+_SIZE=(\d+)$', memory_devices, re.M))
    ram_type = ' / '.join(dict.fromkeys(re.findall(r'^E:MEMORY_DEVICE_\d+_TYPE=(.+)$', memory_devices, re.M)))
except (OSError, ValueError):
    installed_ram = 0
    ram_type = ''

previous = cpu_times()
while True:
    time.sleep(2)
    current = cpu_times()
    cpu = cpu_usage(previous['cpu'], current['cpu'])
    cpu_cores = [dict(id=int(name[3:]), usage=cpu_usage(previous.get(name, current[name]), current[name]))
                 for name in sorted((name for name in current if name != 'cpu'), key=lambda name: int(name[3:]))]
    previous = current
    with open('/proc/meminfo') as source:
        memory = {line.split(':')[0]: int(line.split()[1]) * 1024 for line in source}
    ram_total = max(installed_ram, memory['MemTotal'])
    ram_reserved = ram_total - memory['MemTotal']
    ram_used = ram_total - memory['MemAvailable']
    disk = os.statvfs('/')
    disk_total = disk.f_blocks * disk.f_frsize
    disk_used = (disk.f_blocks - disk.f_bfree) * disk.f_frsize
    disk_free = disk.f_bavail * disk.f_frsize
    with open('/proc/uptime') as source:
        uptime = float(source.read().split()[0])
    print(json.dumps(dict(cpu=max(0, min(100, cpu)), ram=100 * ram_used / ram_total,
                          ramUsed=ram_used, ramTotal=ram_total, ramType=ram_type, ramReserved=ram_reserved, ramAvailable=memory['MemAvailable'],
                          swapUsed=memory['SwapTotal'] - memory['SwapFree'], swapTotal=memory['SwapTotal'], swapBackends=swap_backends(),
                          disk=100 * disk_used / (disk_used + disk_free), diskUsed=disk_used,
                          diskFree=disk_free, diskTotal=disk_total, diskDevice=disk_device,
                          diskFilesystem=disk_filesystem, cpuModel=cpu_model, cores=len(cpu_cores), cpuCores=cpu_cores,
                          load=list(os.getloadavg()), uptime=uptime, hostname=os.uname().nodename, disks=mounted_disks())), flush=True)
