# T3ti Haze Seas

T3ti UI + Haze Seas helper (quests, travel, stats, intro).

## Load (executor)

```lua
local url = "https://raw.githubusercontent.com/nott3ti/t3ti-haze/main/t3ti_haze_bundle.lua"
local src = game:HttpGet(url)
local fn, err = (loadstring or load)(src)
assert(fn, err)
fn()
```

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
