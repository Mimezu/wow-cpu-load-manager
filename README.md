# CPU Load Manager

CPU Load Manager automatically caps CPU-sensitive World of Warcraft settings
according to the current content and restores the player's exact normal values
when the profile no longer applies.

## Use

- Open **Options > AddOns > CPU Load Manager** for the master toggle and status.
- `/cpuload on` enables automation.
- `/cpuload off` disables automation and immediately restores normal settings.
- `/cpuload status` prints the active profile.
- `/cpuload refresh` immediately re-evaluates the current context.
- `/cpuload force auto|normal|city|party|raid10|raid20|large` selects a test profile.
- `/cpuload benchmark [5-60]` samples frame performance for the requested seconds.
- `/cpuload benchclear` clears the saved A/B comparison.
- `/cpuload addcity` adds the current map to the city/hub profile.
- `/cpuload delcity` removes the current map from custom cities/hubs.

The addon is enabled by default. It also restores the baseline during logout or
UI reload so capped values cannot be stranded if the addon is later disabled.
The options panel includes the same manual profile override as a dropdown. Return
it to **Automatic detection** after testing.

## Benchmarking

Force **Normal settings**, run the 15-second benchmark, then force a CPU profile
and run it again in the same place with a comparable camera view. The second run
prints its percentage change against the first. Results include average FPS,
average/p95/p99 frame time, approximate 1% low, long-frame counts, total addon
CPU recent average, and the five heaviest addons exposed by Retail's profiler.

Frame time includes the whole rendered frame; WoW does not expose pure engine CPU
time to addons. With a non-limiting GPU it is a useful CPU/stutter proxy. Addon CPU
metrics cover Lua addon execution only and use Blizzard's rolling recent average.

## Profiles

| Context | Level |
| --- | --- |
| Recognized capital or custom city/hub | Crowd-focused |
| 5-player party/scenario instance | Minor |
| Raid group of 10 or fewer, anywhere | Moderate |
| Raid group of 11-24, anywhere | Strong |
| Raid group of 25+ or PvP/arena instance | Most aggressive |

Profiles cap spell and particle density and—at stronger levels—world
detail, ground clutter, view distance, weather, and sound channel count. The city
profile also hides friendly player names and friendly nameplates. A cap never
raises a value above the player's normal setting.

Retail's base and Raid Graphics copies are capped and restored independently.
The addon never toggles the player's **Use Raid and Battleground Settings**
choice (`RAIDsettingsEnabled`).

GPU-only settings such as render scale, anti-aliasing, texture resolution,
shadows, SSAO, liquid quality, and compute effects are not changed. Projected
textures are never disabled because they can show important encounter mechanics.
Physics level is also left alone because Retail requires a client restart for
that setting; lowering it manually remains a useful one-time CPU optimization.
