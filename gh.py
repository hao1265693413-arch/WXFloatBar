#!/usr/bin/env python3
"""GitHub API 小工具：验证 / 建仓 / 上传 / 触发 / 轮询 / 下载产物"""
import json, os, sys, time, urllib.request, urllib.error, base64, mimetypes

TOKEN = open("/root/.ghtoken").read().strip()
API = "https://api.github.com"


def req(method, path, body=None, raw=False, extra_headers=None, redirect_ok=True):
    url = path if path.startswith("http") else API + path
    data = None
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "minis-wxfb",
    }
    if extra_headers:
        headers.update(extra_headers)
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"

    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            payload = resp.read()
            if raw:
                return payload
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")
        raise SystemExit(f"HTTP {e.code} {method} {url}\n{msg}")


def whoami():
    u = req("GET", "/user")
    print("user:", u["login"])
    return u["login"]


def ensure_repo(owner, name, desc):
    try:
        r = req("GET", f"/repos/{owner}/{name}")
        print("repo exists:", r["full_name"])
        return r
    except SystemExit:
        pass
    body = {"name": name, "description": desc, "private": False, "auto_init": False}
    r = req("POST", "/user/repos", body)
    print("repo created:", r["full_name"], r["html_url"])
    return r


def upload_tree(owner, name, local_root, subdir=""):
    """用 Git Data API 一次性提交整棵树"""
    files = []
    for dp, dns, fns in os.walk(local_root):
        dns[:] = [d for d in dns if d not in ("build", ".git")]
        for fn in fns:
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, local_root).replace(os.sep, "/")
            if subdir:
                rel = subdir + "/" + rel
            files.append((full, rel))

    print(f"uploading {len(files)} files")

    blobs = []
    for full, rel in files:
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        b = req("POST", f"/repos/{owner}/{name}/git/blobs",
                {"content": content, "encoding": "base64"})
        blobs.append({"path": rel, "mode": "100755" if rel.endswith(".sh") else "100644",
                      "type": "blob", "sha": b["sha"]})

    tree = req("POST", f"/repos/{owner}/{name}/git/trees", {"tree": blobs})
    try:
        ref = req("GET", f"/repos/{owner}/{name}/git/ref/heads/main")
        parents = [ref["object"]["sha"]]
    except SystemExit:
        parents = []

    commit = req("POST", f"/repos/{owner}/{name}/git/commits",
                 {"message": "build: WXFloatBar", "tree": tree["sha"], "parents": parents})

    if parents:
        req("PATCH", f"/repos/{owner}/{name}/git/refs/heads/main", {"sha": commit["sha"]})
    else:
        req("POST", f"/repos/{owner}/{name}/git/refs",
            {"ref": "refs/heads/main", "sha": commit["sha"]})
    print("commit:", commit["sha"][:8])
    return commit["sha"]


def trigger(owner, name, workflow):
    req("POST", f"/repos/{owner}/{name}/actions/workflows/{workflow}/dispatches",
        {"ref": "main"})
    print("workflow dispatched")


def latest_run(owner, name):
    r = req("GET", f"/repos/{owner}/{name}/actions/runs?per_page=1")
    runs = r.get("workflow_runs", [])
    return runs[0] if runs else None


def watch(owner, name, timeout=1500):
    start = time.time()
    seen = set()
    while time.time() - start < timeout:
        run = latest_run(owner, name)
        if run:
            rid = run["id"]
            if rid not in seen:
                seen.add(rid)
                print(f"run {rid} status={run['status']} url={run['html_url']}")
            if run["status"] == "completed":
                print("conclusion:", run["conclusion"])
                return run
            if run["status"] == "in_progress":
                print("  ...building")
        time.sleep(15)
    print("timeout")
    return None


if __name__ == "__main__":
    pass
