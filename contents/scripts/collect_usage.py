#!/usr/bin/env python3
"""Collect AI subscription usage limits from every provider signed in locally.

Providers: Claude Code, OpenAI Codex (ChatGPT plan), OpenCode Go, Z.ai GLM
Coding Plan. Each one's credentials are read from where its CLI already
stores them; nothing is sent anywhere except the provider's own endpoint.

Prints one JSON object on stdout and always exits 0:
{
  "providers": [
    {"id": "claude", "name": "Claude", "state": "ok", "detail": "...",
     "windows": [{"id": "five_hour", "label": "5h", "percent": 18.0,
                  "resetsAt": "2026-10-20T14:59:59+00:00"}], "cached": false},
    ...
  ],
  "_fetched_at": 1760000000
}

states: ok | unauthenticated | token_expired | rate_limited | error
Each provider is isolated: one failing never touches the others. A provider
that worked recently keeps serving its cached payload (marked "cached")
until a fetch succeeds again.
"""

import json
import os
import time
import urllib.error
import urllib.request

HOME = os.path.expanduser("~")
CACHE_DIR = os.path.join(HOME, ".cache", "usagelimits")
USER_AGENT = "usagelimits/0.2"
REQUEST_TIMEOUT = 10

CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
CODEX_REFRESH_URL = "https://auth.openai.com/oauth/token"
CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_OAUTH_BETA = "oauth-2025-04-20"
OPENCODE_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
ZAI_QUOTA_URL = "https://api.z.ai/api/monitor/usage/quota/limit"


def http_json(url, headers, timeout=REQUEST_TIMEOUT):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
        return resp.status, json.loads(body), {}
    except urllib.error.HTTPError as e:
        return e.code, None, {}
    except Exception:
        return 0, None, {}


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def iso_from_epoch(value):
    """Epoch seconds or milliseconds to ISO 8601 UTC, or None."""
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if value > 1e11:  # milliseconds
        value /= 1000.0
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(value))
    except (OverflowError, OSError, ValueError):
        return None


def window(id_, label, percent, resets_iso):
    return {"id": id_, "label": label, "percent": round(float(percent), 1),
            "resetsAt": resets_iso or ""}


# --- Claude -----------------------------------------------------------------

def claude_windows(data):
    windows = []
    five = data.get("five_hour") or {}
    seven = data.get("seven_day") or {}
    windows.append(window("five_hour", "5h", five.get("utilization") or 0,
                          five.get("resets_at")))
    windows.append(window("seven_day", "7d", seven.get("utilization") or 0,
                          seven.get("resets_at")))
    for limit in data.get("limits") or []:
        if not isinstance(limit, dict):
            continue
        if limit.get("group") != "weekly" or limit.get("kind") == "weekly_all":
            continue
        percent = limit.get("percent") or 0
        resets = limit.get("resets_at") or ""
        if percent <= 0 and not resets:
            continue
        windows.append(window("weekly_scoped", scoped_label(limit), percent, resets))
    return windows


def scoped_label(limit):
    scope = limit.get("scope") or {}
    name = None
    model = scope.get("model") or {}
    name = model.get("display_name") or model.get("id")
    if not name:
        surface = scope.get("surface")
        if isinstance(surface, str):
            name = surface
        elif isinstance(surface, dict):
            name = surface.get("display_name") or surface.get("id")
    return "Weekly (" + (name or "scoped") + ")"


def collect_claude():
    folder = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    cred_file = os.path.join(folder, ".credentials.json")
    creds = load_json(cred_file)
    oauth = (creds or {}).get("claudeAiOauth") if isinstance(creds, dict) else None
    if not isinstance(oauth, dict) or not oauth.get("accessToken"):
        return {"state": "unauthenticated",
                "detail": "Sign in with: claude (no .credentials.json found)"}

    expires_at = oauth.get("expiresAt") or 0
    try:
        if int(time.time() * 1000) > float(expires_at):
            return {"state": "token_expired",
                    "detail": "Token expired. Run claude in a terminal to refresh."}
    except (TypeError, ValueError):
        pass

    # Identify as the installed Claude Code; the endpoint gates some fields
    # on the client. The token reaches curl... urllib via a header built in
    # process, so it never appears in argv.
    version = "2.1.280"
    versions_dir = os.path.join(HOME, ".local/share/claude/versions")
    try:
        found = [v for v in os.listdir(versions_dir) if v[0].isdigit()]
        if found:
            version = max(found, key=lambda v: [int(x) for x in v.split(".")])
    except OSError:
        pass

    headers = {
        "Authorization": "Bearer " + oauth["accessToken"],
        "anthropic-beta": CLAUDE_OAUTH_BETA,
        "Accept": "application/json",
        "User-Agent": f"claude-cli/{version} (external, cli)",
    }
    status, data, _ = http_json(CLAUDE_USAGE_URL, headers)
    if status == 0:
        return {"state": "error", "detail": "Could not reach the Anthropic API"}
    if status == 429:
        return {"state": "rate_limited", "detail": "Rate limited by Anthropic"}
    if status in (401, 403):
        return {"state": "token_expired",
                "detail": "Token rejected. Run claude in a terminal to refresh."}
    if status != 200 or not isinstance(data, dict):
        return {"state": "error", "detail": f"API returned HTTP {status}"}
    if "error" in data:
        msg = data["error"]
        if isinstance(msg, dict):
            msg = msg.get("message", str(data))
        return {"state": "error", "detail": str(msg)}
    return {"state": "ok", "detail": "", "windows": claude_windows(data)}


# --- Codex (ChatGPT plan) ---------------------------------------------------

def codex_tokens(auth):
    tokens = auth.get("tokens")
    if isinstance(tokens, dict):
        return tokens
    if isinstance(auth.get("access_token"), str):
        return auth
    return None


def refresh_codex_token(auth, refresh_token):
    """Exchange the refresh token and write auth.json back in place, keeping
    the inode: other tools may hold hardlinks to the same file."""
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": CODEX_CLIENT_ID,
        "refresh_token": refresh_token,
    }).encode()
    req = urllib.request.Request(
        CODEX_REFRESH_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            payload = json.load(resp)
    except Exception:
        return None
    access = payload.get("access_token")
    if not isinstance(access, str) or not access:
        return None
    tokens = codex_tokens(auth)
    if tokens is None:
        return None
    tokens["access_token"] = access
    for key in ("refresh_token", "id_token"):
        if isinstance(payload.get(key), str) and payload[key]:
            tokens[key] = payload[key]
    auth_path = os.path.join(
        os.environ.get("CODEX_HOME") or os.path.join(HOME, ".codex"), "auth.json")
    try:
        with os.fdopen(os.open(auth_path, os.O_WRONLY), "wb") as stream:
            data = json.dumps(auth, separators=(",", ":")).encode()
            stream.write(data)
            stream.truncate(len(data))
    except OSError:
        pass
    return access


def codex_window(raw, id_, fallback_label):
    if not isinstance(raw, dict):
        return None
    percent = raw.get("used_percent")
    if percent is None:
        percent = raw.get("used_percentage") or raw.get("usedPercentage")
    if percent is None:
        return None
    duration = raw.get("limit_window_seconds")
    label = fallback_label
    try:
        label = "5h" if float(duration) <= 24 * 60 * 60 else "7d"
    except (TypeError, ValueError):
        pass
    return window(id_, label, percent, iso_from_epoch(raw.get("reset_at") or raw.get("resets_at")))


def collect_codex():
    auth_path = os.path.join(
        os.environ.get("CODEX_HOME") or os.path.join(HOME, ".codex"), "auth.json")
    auth = load_json(auth_path)
    tokens = codex_tokens(auth) if isinstance(auth, dict) else None
    if not tokens or not isinstance(tokens.get("access_token"), str):
        return {"state": "unauthenticated",
                "detail": "Sign in with: codex (ChatGPT plan login not found)"}

    headers = {
        "Authorization": "Bearer " + tokens["access_token"],
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }
    if isinstance(tokens.get("account_id"), str) and tokens["account_id"]:
        headers["ChatGPT-Account-Id"] = tokens["account_id"]

    status, data, _ = http_json(CODEX_USAGE_URL, headers)
    if status in (401, 403) and isinstance(tokens.get("refresh_token"), str):
        refreshed = refresh_codex_token(auth, tokens["refresh_token"])
        if refreshed:
            headers["Authorization"] = "Bearer " + refreshed
            status, data, _ = http_json(CODEX_USAGE_URL, headers)

    if status == 0:
        return {"state": "error", "detail": "Could not reach the Codex usage API"}
    if status == 429:
        return {"state": "rate_limited", "detail": "Codex usage endpoint is rate-limited"}
    if status in (401, 403):
        return {"state": "unauthenticated",
                "detail": "Codex login expired. Run: codex"}
    if status != 200 or not isinstance(data, dict):
        return {"state": "error", "detail": f"Codex usage returned HTTP {status}"}

    rate_limit = data.get("rate_limit")
    if not isinstance(rate_limit, dict):
        return {"state": "error", "detail": "Codex returned no rate-limit windows"}

    windows = []
    for id_, slot, label in (("five_hour", "primary_window", "5h"),
                             ("seven_day", "secondary_window", "7d")):
        win = codex_window(rate_limit.get(slot), id_, label)
        if win:
            windows.append(win)
    if not windows:
        return {"state": "error", "detail": "Codex returned empty rate-limit windows"}

    detail = data.get("plan_type")
    detail = f"ChatGPT {detail}" if isinstance(detail, str) and detail else "ChatGPT plan"
    return {"state": "ok", "detail": detail, "windows": windows}


# --- OpenCode Go ------------------------------------------------------------

def collect_opencode():
    auth = load_json(os.path.join(HOME, ".local/share/opencode/auth.json"))
    entry = (auth or {}).get("opencode-go")
    key = entry.get("key") if isinstance(entry, dict) else None
    if not key:
        return {"state": "unauthenticated",
                "detail": "Run opencode /connect and add OpenCode Go"}

    status, data, _ = http_json(OPENCODE_USAGE_URL, {
        "Authorization": "Bearer " + key,
        "Accept": "application/json",
        "User-Agent": USER_AGENT,  # requests without one get 403
    })
    if status == 0:
        return {"state": "error", "detail": "Could not reach opencode.ai"}
    if status == 429:
        return {"state": "rate_limited", "detail": "opencode.ai is rate-limiting"}
    if status in (401, 403):
        return {"state": "unauthenticated",
                "detail": "OpenCode Go key rejected. Reconnect in opencode."}
    if status != 200 or not isinstance(data, dict):
        return {"state": "error", "detail": f"OpenCode usage returned HTTP {status}"}

    usage = data.get("usage")
    if not isinstance(usage, dict):
        return {"state": "error", "detail": "OpenCode returned no usage object"}

    windows = []
    for id_, label in (("rolling", "5h"), ("weekly", "Weekly"), ("monthly", "Monthly")):
        raw = usage.get(id_)
        if not isinstance(raw, dict):
            continue
        if raw.get("status") not in (None, "ok"):
            continue
        percent = raw.get("percent")
        if percent is None:
            continue
        windows.append(window(id_, label, percent, raw.get("resetsAt")))
    if not windows:
        return {"state": "error", "detail": "OpenCode returned no usage windows"}
    return {"state": "ok", "detail": "OpenCode Go", "windows": windows}


# --- Z.ai GLM Coding Plan ---------------------------------------------------

def zai_api_key():
    # 1. explicit file, 2. environment, 3. opencode config (MCP env block).
    key_file = os.path.join(HOME, ".config/usagelimits/zai-api-key")
    if os.path.isfile(key_file):
        try:
            with open(key_file) as f:
                key = f.read().strip()
            if key:
                return key
        except OSError:
            pass
    if os.environ.get("Z_AI_API_KEY"):
        return os.environ["Z_AI_API_KEY"]
    cfg = load_json(os.path.join(HOME, ".config/opencode/opencode.json"))
    if isinstance(cfg, dict):
        for server in (cfg.get("mcp") or {}).values():
            env = (server or {}).get("environment") or {}
            if env.get("Z_AI_API_KEY"):
                return env["Z_AI_API_KEY"]
    return None


ZAI_UNIT_LABELS = {2: "min", 3: "h", 4: "d", 5: "Weekly", 6: "Monthly"}


def zai_window_label(limit):
    try:
        unit = int(limit.get("unit"))
        number = int(limit.get("number"))
    except (TypeError, ValueError):
        return "Window"
    name = ZAI_UNIT_LABELS.get(unit)
    if name in ("Weekly", "Monthly"):
        return name
    if name:
        return f"{number}{name}"
    return f"{number}·u{unit}"


def collect_zai():
    key = zai_api_key()
    if not key:
        return {"state": "unauthenticated",
                "detail": "No Z.ai API key. Save one in ~/.config/usagelimits/zai-api-key"}

    status, data, _ = http_json(ZAI_QUOTA_URL, {
        "Authorization": "Bearer " + key,
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    })
    if status == 0:
        return {"state": "error", "detail": "Could not reach api.z.ai"}
    if status == 429:
        return {"state": "rate_limited", "detail": "api.z.ai is rate-limiting"}
    if status in (401, 403):
        return {"state": "unauthenticated", "detail": "Z.ai API key rejected"}
    if status != 200 or not isinstance(data, dict):
        return {"state": "error", "detail": f"Z.ai usage returned HTTP {status}"}

    payload = data.get("data") if isinstance(data.get("data"), dict) else data
    limits = payload.get("limits")
    if not isinstance(limits, list) or not limits:
        return {"state": "error", "detail": "Z.ai returned no quota limits"}

    windows = []
    for limit in limits:
        if not isinstance(limit, dict):
            continue
        kind = limit.get("type")
        percent = limit.get("percentage")
        if percent is None and limit.get("usage"):
            try:
                usage = float(limit["usage"])
                current = limit.get("currentValue")
                if current is not None:
                    percent = float(current) / usage * 100
            except (TypeError, ValueError, ZeroDivisionError):
                percent = None
        if percent is None:
            continue
        label = "MCP" if kind == "TIME_LIMIT" else zai_window_label(limit)
        resets = iso_from_epoch(limit.get("nextResetTime"))
        windows.append(window(f"zai_{len(windows)}", label, percent, resets))
    if not windows:
        return {"state": "error", "detail": "Z.ai quota response had no readable windows"}

    windows.sort(key=lambda w: 0 if w["label"] == "MCP" else 1)
    plan = payload.get("planName") or payload.get("plan") or payload.get("packageName") or "GLM Coding Plan"
    return {"state": "ok", "detail": str(plan), "windows": windows}


# --- Assembly ---------------------------------------------------------------

PROVIDERS = (
    ("claude", "Claude", collect_claude),
    ("codex", "Codex", collect_codex),
    ("opencode", "OpenCode Go", collect_opencode),
    ("zai", "Z.ai", collect_zai),
)


def cache_path(provider_id):
    return os.path.join(CACHE_DIR, f"{provider_id}.json")


def collect_provider(provider_id, collector):
    try:
        result = collector()
        if not isinstance(result, dict):
            raise ValueError("collector returned a non-dict")
    except Exception as e:
        result = {"state": "error", "detail": f"{type(e).__name__}: {e}"}

    if result.get("state") == "ok":
        result["cached"] = False
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            tmp = cache_path(provider_id) + ".tmp"
            with open(tmp, "w") as f:
                json.dump(result, f)
            os.replace(tmp, cache_path(provider_id))
        except OSError:
            pass
        return result

    cached = load_json(cache_path(provider_id))
    if isinstance(cached, dict) and cached.get("state") == "ok":
        cached["cached"] = True
        if result.get("detail"):
            cached["notice"] = result["detail"]
        return cached
    result["cached"] = False
    return result


def main():
    providers = []
    for provider_id, name, collector in PROVIDERS:
        result = collect_provider(provider_id, collector)
        result["id"] = provider_id
        result["name"] = name
        providers.append(result)

    print(json.dumps({"providers": providers, "_fetched_at": int(time.time())}))


if __name__ == "__main__":
    main()
