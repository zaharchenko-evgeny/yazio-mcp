# Running yazio-mcp in an isolated Docker container

This image runs the (unofficial) Yazio MCP server as a hardened, non‑root,
read‑only container. Because it's a **stdio** MCP server, it has **no ports**
and isn't a long‑running web service — your MCP client launches it on demand.

## 1. Create your credentials file

Copy the example and fill in your Yazio login. This file stays on your machine
and is gitignored; it is **not** baked into the image.

```bash
cp .env.example .env
# edit .env:
#   YAZIO_USERNAME=you@example.com
#   YAZIO_PASSWORD=your_yazio_password
```

## 2. Build the image (from your reviewed local checkout)

```bash
docker compose build
# or, without compose:
docker build -t yazio-mcp:local .
```

This builds from the local source and pinned `package-lock.json` — not from
`npx`/npm "latest" — so you run exactly the code you reviewed.

## 3. Smoke‑test it

```bash
docker compose run --rm yazio-mcp
```

With valid credentials you'll see, on stderr:
`✅ Successfully authenticated with Yazio ...` and
`Yazio MCP server running on stdio`. It then waits for MCP traffic on stdin —
press `Ctrl‑C` to exit. With no/bad credentials it prints an error and exits 1
(it fails closed — verified).

## 4. Point your MCP client at the container

The client should launch the container per‑session over stdio. Use the same
hardening flags as the compose file:

### Claude Desktop / Claude Code / Cursor config

```json
{
  "mcpServers": {
    "yazio": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--env-file", "/ABSOLUTE/PATH/TO/yazio-mcp/.env",
        "--user", "node",
        "--read-only",
        "--tmpfs", "/tmp:size=16m,mode=1777",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--memory", "256m",
        "--pids-limit", "128",
        "--cpus", "0.5",
        "--network", "bridge",
        "yazio-mcp:local"
      ]
    }
  }
}
```

Claude Code one‑liner equivalent:

```bash
claude mcp add yazio -- docker run --rm -i \
  --env-file /ABSOLUTE/PATH/TO/yazio-mcp/.env \
  --user node --read-only --tmpfs /tmp:size=16m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --memory 256m --pids-limit 128 --cpus 0.5 \
  yazio-mcp:local
```

Replace `/ABSOLUTE/PATH/TO/yazio-mcp/` with this folder's real path.

## Isolation profile (what each flag buys you)

| Control | Flag | Effect |
|---|---|---|
| Non‑root | `--user node` | Process can't act as root inside the container |
| Read‑only FS | `--read-only` + tmpfs | No persistence; can't drop files or modify the image |
| No capabilities | `--cap-drop ALL` | Removes all Linux privileges (raw sockets, mount, etc.) |
| No privilege escalation | `--security-opt no-new-privileges:true` | setuid/sudo can't elevate |
| Resource caps | `--memory/--pids-limit/--cpus` | A runaway/compromised process can't exhaust the host |
| No inbound | (stdio only) | No published ports; unreachable from your network |
| Ephemeral | `--rm` | Container is destroyed after each session |

## About network egress

The server **must** reach Yazio's API (`https://yzapi.yazio.com`) over HTTPS to
authenticate and fetch data, so the network can't be set to `none`. There is no
**inbound** exposure. If you want to restrict **outbound** traffic to only
Yazio, the simplest robust option is a dedicated user‑defined network plus an
egress firewall/proxy on the host (e.g. allow only Yazio's domain). For most
threat models the read‑only, capability‑dropped, non‑root sandbox above is
sufficient, since the code only ever contacts Yazio anyway (verified in the
security review).

## Updating

When you pull new commits, re‑review the diff (especially `package-lock.json`),
then `docker compose build` again. The image only ever contains the code you
built locally.
