#!/usr/bin/env python3
# docker-stats.py — one JSON blob for DockerHub widget:
# overview (running/total/healthy/images/disk) + containers grouped by compose project,
# each with live CPU%/MEM (from `docker stats`), ports, image, uptime, health, state.
# No sudo needed (user is in the `docker` group). Mirrors perf-stats.py: a bad sample
# prints an error object rather than crashing the widget.
import json, re, subprocess

DOCKER = "docker"

def run(args, timeout=6):
    return subprocess.run([DOCKER, *args], capture_output=True, text=True, timeout=timeout)


def parse_ports(s):
    # "0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp" -> ["5433→5432"] (deduped)
    seen, out = set(), []
    for m in re.finditer(r":(\d+)->(\d+)", s or ""):
        key = m.group(1) + "->" + m.group(2)
        if key not in seen:
            seen.add(key); out.append(m.group(1) + "→" + m.group(2))
    return out


def label(labels, key):
    m = re.search(r"(?:^|,)com\.docker\.compose\." + key + r"=([^,]*)", labels or "")
    return m.group(1) if m else ""


def clean_status(status):
    # "Up About an hour (healthy)" -> "Up About an hour"; leave exited strings intact
    return re.sub(r"\s*\((?:healthy|unhealthy|health: starting)\)\s*$", "", status or "").strip()


try:
    ps = run(["ps", "-a", "--format", "{{json .}}"])
    if ps.returncode != 0:
        err = "daemon" if "Cannot connect to the Docker daemon" in ps.stderr else "error"
        print(json.dumps({"ok": False, "error": err, "detail": ps.stderr.strip()[:200]}))
        raise SystemExit(0)

    containers = []
    for line in ps.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            c = json.loads(line)
        except ValueError:
            continue
        containers.append({
            "id": c.get("ID", ""),
            "name": c.get("Names", "").split(",")[0],
            "image": c.get("Image", ""),
            "state": c.get("State", ""),
            "status": clean_status(c.get("Status", "")),
            "health": c.get("HealthStatus", ""),      # healthy|unhealthy|starting|""
            "ports": parse_ports(c.get("Ports", "")),
            "project": label(c.get("Labels", ""), "project"),
            "service": label(c.get("Labels", ""), "service"),
            "cpu": 0.0, "memPerc": 0.0, "memUsage": "",
        })

    # live CPU/MEM for running containers, merged by short ID
    stats = {}
    try:
        st = run(["stats", "--no-stream", "--format", "{{json .}}"])
        if st.returncode == 0:
            for line in st.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    s = json.loads(line)
                except ValueError:
                    continue
                stats[s.get("ID", "")] = s
    except Exception:
        pass
    for c in containers:
        s = stats.get(c["id"])
        if s:
            try: c["cpu"] = round(float(s.get("CPUPerc", "0").rstrip("%")), 1)
            except ValueError: pass
            try: c["memPerc"] = round(float(s.get("MemPerc", "0").rstrip("%")), 1)
            except ValueError: pass
            c["memUsage"] = (s.get("MemUsage", "") or "").split("/")[0].strip()

    # overview
    total = len(containers)
    running = sum(1 for c in containers if c["state"] == "running")
    healthy = sum(1 for c in containers if c["health"] == "healthy")
    unhealthy = sum(1 for c in containers if c["health"] == "unhealthy")
    images_count, images_size = 0, "—"
    try:
        df = run(["system", "df", "--format", "{{json .}}"])
        if df.returncode == 0:
            for line in df.stdout.splitlines():
                try: d = json.loads(line)
                except ValueError: continue
                if d.get("Type") == "Images":
                    images_count = int(d.get("TotalCount", 0) or 0)
                    images_size = d.get("Size", "—")
    except Exception:
        pass

    # group by compose project (loose containers under "")
    order, groups = [], {}
    for c in containers:
        p = c["project"]
        if p not in groups:
            groups[p] = []; order.append(p)
    for c in containers:
        groups[c["project"]].append(c)
    # sort: named projects first (alpha), loose "" last; running before stopped within a group
    named = sorted([p for p in order if p], key=str.lower)
    ordered = named + ([""] if "" in groups else [])
    grouped = [{
        "project": p if p else "—",
        "containers": sorted(groups[p], key=lambda c: (c["state"] != "running", c["name"].lower())),
    } for p in ordered]

    print(json.dumps({
        "ok": True,
        "overview": {"running": running, "total": total, "healthy": healthy,
                     "unhealthy": unhealthy, "images": images_count, "disk": images_size},
        "groups": grouped,
    }))
except subprocess.TimeoutExpired:
    print(json.dumps({"ok": False, "error": "timeout"}))
except SystemExit:
    pass
except Exception as e:
    print(json.dumps({"ok": False, "error": "exception", "detail": str(e)[:200]}))
