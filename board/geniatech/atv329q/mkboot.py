#!/usr/bin/env python3
# Minimal Android (qcom, with appended QCDT) bootimg builder, matching the
# header layout of the original atv329q boot image.
import struct, hashlib, sys, os

def pad(b, page):
    r = len(b) % page
    return b + (b'\x00' * (page - r) if r else b'')

def build(kernel, ramdisk, dt, cmdline, page=2048,
          kaddr=0x80008000, raddr=0x84000000, saddr=0x80f00000,
          tags=0x80000100):
    # FIX 2026-06-17: raddr was 0x81000000 -> the 10MB zImage decompresses to
    # 27MB from kaddr 0x80008000 (up to ~0x81b00000), CLOBBERING a ramdisk at
    # 0x81000000 -> initramfs corrupted -> init never runs -> reset before init.
    # drm-final-boot.img (known-good) loads the ramdisk at 0x84000000. Match it.
    second = b''
    # id: sha1 over (kernel|ksz|ramdisk|rsz|second|ssz|dt|dtsz) like qcom mkbootimg
    sha = hashlib.sha1()
    for part in (kernel, ramdisk, second, dt):
        sha.update(part)
        sha.update(struct.pack('<I', len(part)))
    img_id = sha.digest()[:20] + b'\x00' * 12  # 32-byte id field

    cmd = cmdline.encode() if isinstance(cmdline, str) else cmdline
    assert len(cmd) <= 512
    hdr = b'ANDROID!'
    hdr += struct.pack('<10I',
        len(kernel), kaddr,
        len(ramdisk), raddr,
        len(second), saddr,
        tags, page,
        len(dt), 0)
    hdr += b'\x00' * 16            # name[16]
    hdr += cmd + b'\x00' * (512 - len(cmd))   # cmdline[512]
    hdr += img_id                 # id[32] -> total 64+40+512+32... actually pad to page below

    out = pad(hdr, page)
    out += pad(kernel, page)
    out += pad(ramdisk, page)
    if second:
        out += pad(second, page)
    out += pad(dt, page)
    return out

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--kernel', required=True)
    p.add_argument('--ramdisk', required=True)
    p.add_argument('--dt', required=True)
    p.add_argument('--cmdline', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--page', type=int, default=2048)
    a = p.parse_args()
    cmd = open(a.cmdline, 'rb').read().rstrip(b'\x00').decode()
    img = build(open(a.kernel,'rb').read(),
                open(a.ramdisk,'rb').read(),
                open(a.dt,'rb').read(),
                cmd, page=a.page)
    open(a.out,'wb').write(img)
    print(f"wrote {a.out} ({len(img)} bytes)")
