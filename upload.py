#!/usr/bin/env python3
"""用 Contents API 逐文件提交（空仓库也能用）"""
import os, sys, base64
import gh

owner = "hao1265693413-arch"
repo = "WXFloatBar"
root = "/var/minis/workspace/WXFloatBar"

files = []
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d not in ("build", ".git", "__pycache__")]
    for fn in fns:
        if fn.endswith(".pyc"):
            continue
        full = os.path.join(dp, fn)
        rel = os.path.relpath(full, root).replace(os.sep, "/")
        files.append((full, rel))

# 先传 README（建立首个提交），再传其余
files.sort(key=lambda x: (x[1] != "README.md", x[1]))
print(f"{len(files)} files")

for full, rel in files:
    with open(full, "rb") as f:
        content = base64.b64encode(f.read()).decode()
    body = {"message": f"add {rel}", "content": content, "branch": "main"}
    try:
        r = gh.req("PUT", f"/repos/{owner}/{repo}/contents/{rel}", body)
        print("  ok:", rel)
    except SystemExit as e:
        print("  skip:", rel, str(e)[:80])
