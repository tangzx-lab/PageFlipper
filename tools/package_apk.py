#!/usr/bin/env python3
"""Add classes.dex to an aapt2-linked resource APK without changing resources."""
import os
import sys
import zipfile


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: package_apk.py <resources.apk> <classes.dex> <output.apk>")
        return 2
    src, dex, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    tmp = dst + ".tmp"
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(tmp, "w") as zout:
        for item in zin.infolist():
            zout.writestr(item, zin.read(item.filename))
        zout.write(dex, "classes.dex", compress_type=zipfile.ZIP_DEFLATED)
    os.replace(tmp, dst)
    print(f"packaged {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
