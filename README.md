These are just some apps i've modified or created for my tronbyt.

## Apps that follow the device timezone

`mlb-scores`, `mlb-game`, `mlb-leaders`, and `nationaltoday` use the timezone
configured for the Tronbyt device through Pixlet's `time.tz()` API. They have no
fixed regional timezone. Legacy app-level `location` or `timezone` values are
ignored by these four apps, so game times, schedule dates, season years, holiday
dates, and holiday QR links all follow the same device setting.

MLB Game formats the abbreviation at the game instant, including daylight-saving
time where applicable. `MST` in its Go-style time format is a layout token: it
produces the actual zone abbreviation (for example MST, EST, or EDT).

These apps are adapted from [tronbyt/apps](https://github.com/tronbyt/apps) at
commit `55060e2ba537505af8791f38a7cae0ea45a8f1d4`, with the original author
metadata retained. Each added app directory includes the upstream Apache 2.0
license. Existing personal apps are unchanged. These copies follow this
repository's Git updates; new community changes need to be merged deliberately.

Run the offline timezone fixtures with Pixlet v0.54.0 or compatible:

```sh
PIXLET=/path/to/pixlet python3 -m unittest discover -s tests -p 'test_device_timezones.py' -v
```
