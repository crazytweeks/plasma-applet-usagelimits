# Usage Limits

A KDE Plasma 6 panel widget that monitors the subscription usage of six AI
CLIs at once: **Claude Code**, **OpenAI Codex (ChatGPT plan)**, **OpenCode Go**,
**Z.ai (GLM Coding Plan)**, **Google Antigravity**, and **Command Code**.

## Features

- All six providers in one widget; each can be shown or hidden in settings
- Whatever windows each provider reports: 5-hour, weekly, monthly, credits
- Three-ish panel styles for different panel sizes and seven in total:
  **rings** (round gauge per provider), **glow** (chip brightness = usage),
  **capsule** (one segmented strip), **dots** (smallest), plus the original
  **bars**, **letters+percentages**, and **worst** pill
- Popup with one card per provider: per-window usage, reset countdowns,
  plan names, and manual refresh
- Bars tinted by warning/critical thresholds (configurable colors)
- Providers are isolated: one failing never hides the others, and a provider
  that worked recently keeps serving cached data (marked "cached") until a
  fetch succeeds again

## How It Works

`contents/scripts/collect_usage.py` runs on every poll. It reads each CLI's
own credentials from where the CLI already stores them and calls each
provider's own usage endpoint. Nothing is sent anywhere else.

| Provider | Credentials | Endpoint |
|---|---|---|
| Claude | `~/.claude/.credentials.json` | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` (auto-refreshes the token) | `chatgpt.com/backend-api/wham/usage` |
| OpenCode Go | `~/.local/share/opencode/auth.json` (`opencode-go` key) | `opencode.ai/zen/go/v1/usage` |
| Z.ai | API key: `~/.config/usagelimits/zai-api-key`, `Z_AI_API_KEY`, or your opencode config | `api.z.ai/api/monitor/usage/quota/limit` |
| Antigravity | Google OAuth: found automatically (T3 / `agy` logins, `~/.codexbar`), or an explicit file `~/.config/usagelimits/antigravity-oauth.json` | `daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` (+ `retrieveUserQuota` fallback) |
| Command Code | `cmd login` (`~/.commandcode/auth.json`), `COMMAND_CODE_API_KEY`, or a `user_...` key in `~/.config/usagelimits/commandcode-api-key` | `api.commandcode.ai/alpha/billing/credits` (+ `/billing/subscriptions`) |

If a provider isn't signed in, its row says so instead of failing silently.
Sign in with `claude` / `codex` / `opencode /connect` / `agy` / `cmd login` in
a terminal; for Z.ai save an API key to `~/.config/usagelimits/zai-api-key`.

Antigravity notes: the widget reads your Google subscription quota
weekly + 5-hour limits for both model families the CLI shows, plus the
per-model 5-hour window. Only remote OAuth endpoints are used — keep the Antigravity
app signed in if you also use it locally. The Gemini *weekly* allowance is not
exposed by the remote endpoints and may be absent; the other three windows are
always reported.

> These widgets use internal endpoints that are not public, documented APIs.
> They may change or stop working without notice.

## Requirements

- KDE Plasma 6
- `python3` (the collector uses only the standard library)

## Install

```sh
bash install.sh
```

Then add **Usage Limits** to your panel (or test standalone with
`plasmawindowed com.bhuvan.usagelimits`). To see data you need at least one
of the four CLIs signed in — the widget shows "not signed in" for the rest.

## Uninstall

```sh
kpackagetool6 -t Plasma/Applet -r com.bhuvan.usagelimits
```

## Configuration

Right-click the widget and choose **Configure...**:

- **Providers** — show/hide each of the six individually
- **Panel style** — rings / glow / capsule / dots / bars / letters+percentages /
  worst-pill, sized for anything from thin vertical panels to wide panels
- **Color theme** — presets (Warm, Sunset, Nord, Mono) or fully custom colors
- Poll interval (default 15 minutes; these endpoints rate-limit hard)
- Warning / critical thresholds
- Normal / warning bar colors

## License

MIT
