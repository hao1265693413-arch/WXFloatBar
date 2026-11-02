#!/usr/bin/env python3
"""
纯 Python 打 rootless deb，不依赖 dpkg-deb / md5sum / GNU sed。
用法: pack_deb.py <pkgroot> <out.deb> <version>
"""
import os, sys, tarfile, hashlib, io, time

PKG = "com.hao.wxfloatbar"
NAME = "WXFloatBar"


def add_file(tar, path, arcname):
    """以 root:wheel 写入，保证 iOS 上权限正确"""
    info = tar.gettarinfo(path, arcname)
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    info.mode = 0o644 if os.path.isfile(path) else 0o755
    info.mtime = int(time.time())
    if os.path.isfile(path):
        with open(path, "rb") as f:
            tar.addfile(info, f)
    else:
        tar.addfile(info)


def tar_bytes(root, exclude_debian=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            rel_dir = os.path.relpath(dirpath, root)
            if rel_dir == ".":
                rel_dir = ""
            if exclude_debian and rel_dir.split(os.sep)[0] == "DEBIAN":
                continue
            for d in dirnames:
                full = os.path.join(dirpath, d)
                arc = os.path.join(rel_dir, d) if rel_dir else d
                if exclude_debian and arc.split(os.sep)[0] == "DEBIAN":
                    continue
                add_file(tar, full, "./" + arc)
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                arc = os.path.join(rel_dir, fn) if rel_dir else fn
                if exclude_debian and arc.split(os.sep)[0] == "DEBIAN":
                    continue
                add_file(tar, full, "./" + arc)
    return buf.getvalue()


def ar_archive(members):
    """生成标准 ar 归档（deb 格式）"""
    out = io.BytesIO()
    out.write(b"!<arch>\n")
    for name, data in members:
        header = "{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n".format(
            name, 0, 0, 0, "100644", len(data)
        )
        out.write(header.encode("ascii"))
        out.write(data)
        if len(data) % 2 == 1:
            out.write(b"\n")
    return out.getvalue()


def main():
    root, out_path, version = sys.argv[1], sys.argv[2], sys.argv[3]

    # 计算 Installed-Size
    total_kb = 0
    for dp, _, fns in os.walk(root):
        for fn in fns:
            total_kb += os.path.getsize(os.path.join(dp, fn))
    total_kb = max(1, total_kb // 1024)

    control = f"""Package: {PKG}
Name: {NAME}
Version: {version}
Architecture: iphoneos-arm64
Description: 微信液态玻璃悬浮底栏 · 拖拽吸附 · 液态高光滑动 · 支持 TrollStore 注入
Maintainer: hao
Author: hao
Section: Tweaks
Depends: mobilesubstrate
Installed-Size: {total_kb}
"""

    debian_dir = os.path.join(root, "DEBIAN")
    os.makedirs(debian_dir, exist_ok=True)
    with open(os.path.join(debian_dir, "control"), "w") as f:
        f.write(control)

    # md5sums
    lines = []
    for dp, dns, fns in os.walk(root):
        dns.sort()
        if os.path.relpath(dp, root).split(os.sep)[0] == "DEBIAN":
            continue
        for fn in sorted(fns):
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, root)
            with open(full, "rb") as f:
                lines.append(hashlib.md5(f.read()).hexdigest() + "  " + rel)
    with open(os.path.join(debian_dir, "md5sums"), "w") as f:
        f.write("\n".join(lines) + "\n")

    data_tgz = tar_bytes(root, exclude_debian=True)
    control_tgz = tar_bytes(debian_dir, exclude_debian=False)

    blob = ar_archive([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", control_tgz),
        ("data.tar.gz", data_tgz),
    ])

    with open(out_path, "wb") as f:
        f.write(blob)
    print(f"OK -> {out_path} ({len(blob)} bytes, Installed-Size {total_kb}KB)")


if __name__ == "__main__":
    main()
