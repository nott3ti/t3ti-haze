# T3ti Haze Seas

Private T3ti UI + Haze Seas helper (quests, travel, stats, intro).

## Load (executor)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/nott3ti/t3ti-haze/main/t3ti_haze_bundle.lua"))()
```

> Private repo: raw GitHub URLs won’t work without auth. Invite collaborators → they `git clone` → `loadstring(readfile("t3ti_haze_bundle.lua"))()`.

## Controls
- **RCtrl** — toggle menu
- Intro plays once on launch (~7s delay, ends ~12s)

## Requirements
- Executor with Drawing API, `HttpGet`, `writefile`, `getcustomasset`
- For intro audio: `writefile` + `getcustomasset` (wav is in `t3ti-intro/`)

## Files
- `t3ti_haze_bundle.lua` — all-in-one
- `t3ti_ui.lua` / `haze_seas_helper.lua` — split sources
- `t3ti-intro/untitled.wav` — intro jingle
