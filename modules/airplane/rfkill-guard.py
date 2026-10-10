import fcntl
import os
import struct
import sys

STATE = sys.argv[1]
RFKILL_IOCTL_NOINPUT = 0x5201
EVENT = struct.Struct("=IBBBB")
OP_ADD, OP_CHANGE = 0, 2
NAMES = {1: "wlan", 2: "bluetooth"}


def airplane_on():
    try:
        with open(STATE) as f:
            return f.read().strip() == "on"
    except OSError:
        return False


fd = os.open("/dev/rfkill", os.O_RDWR)
fcntl.ioctl(fd, RFKILL_IOCTL_NOINPUT)
print("kernel rfkill key handler disabled while this guard runs", flush=True)
while True:
    idx, kind, op, soft, hard = EVENT.unpack(os.read(fd, 8)[: EVENT.size])
    if kind not in NAMES or op not in (OP_ADD, OP_CHANGE) or airplane_on():
        continue
    if hard:
        print(f"{NAMES[kind]} rfkill{idx} hard-blocked outside `airplane`", flush=True)
    if soft:
        print(f"{NAMES[kind]} rfkill{idx} soft-blocked outside `airplane`; unblocking", flush=True)
        os.write(fd, EVENT.pack(idx, kind, OP_CHANGE, 0, 0))
