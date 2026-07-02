#!/usr/bin/env python3
# Build a QCDT v3 (dt.img) wrapping a SINGLE dtb, with the atv329q vendor
# board-id table (12 entries) so the stock aboot matches and boots it directly
# (no lk2nd).  Metadata board-ids extracted from the vendor QCDT:
#   platform {245,258,265,275} x subtype {81,82,136}, variant 65547, pmic0 65549.
import struct, sys

ENTRIES = [(p, 65547, s, 0, 65549, 0, 0, 0)
           for p in (245, 258, 265, 275) for s in (81, 82, 136)]

def build(dtb, dt_off=0x800):
    dtb_pad = dtb + (b'\x00' * ((4 - len(dtb) % 4) % 4))
    hdr = b'QCDT' + struct.pack('<II', 3, len(ENTRIES))
    tbl = b''.join(struct.pack('<10I', *(e + (dt_off, len(dtb_pad)))) for e in ENTRIES)
    meta = hdr + tbl
    assert len(meta) <= dt_off, "metadata larger than dtb offset"
    meta += b'\x00' * (dt_off - len(meta))
    return meta + dtb_pad

if __name__ == '__main__':
    dtb = open(sys.argv[1], 'rb').read()
    out = build(dtb)
    open(sys.argv[2], 'wb').write(out)
    print("wrote %s (%d bytes, dtb=%d)" % (sys.argv[2], len(out), len(dtb)))
