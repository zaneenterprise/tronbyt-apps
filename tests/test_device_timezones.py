"""Offline regression tests using Pixlet's real Starlark/time implementation.

Run with Pixlet on PATH, or set PIXLET to the executable:
    python3 -B -m unittest discover -s tests -v

Only HTTP and the current instant are mocked. Each render gets its own TZ
environment value, while time.tz(), parsing, and timezone conversion remain
Pixlet's implementations. All HTTP requests must match in-memory fixtures;
these tests do not access the network or require accounts/personal settings.
Optional TIMEZONE_TEST_RESULTS names a JSON evidence file to write.
"""

from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[1]
PIXLET = os.environ.get("PIXLET") or shutil.which("pixlet")
SCORES = ROOT / "apps/mlb-scores/mlb_scores.star"
GAME = ROOT / "apps/mlb-game/mlb_game.star"
LEADERS = ROOT / "apps/mlb-leaders/mlb_leaders.star"
HOLIDAYS = ROOT / "apps/nationaltoday/nationaltoday.star"
ESPN = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
MLB = "https://statsapi.mlb.com/api/v1"
PHOENIX = "America/Phoenix"
EASTERN = "America/New_York"
RESULTS = []


def literal(value):
    """Represent JSON values without Python/Starlark boolean spelling issues."""
    return "json.decode(%s)" % json.dumps(json.dumps(value))


def stale_settings(device_timezone):
    """A synthetic legacy app configuration intentionally disagrees with TZ."""
    other = EASTERN if device_timezone == PHOENIX else PHOENIX
    return {"timezone": other,
            "location": {"lat": "0", "lng": "0", "locality": "Fixture", "timezone": other}}


def placeholder_png():
    """A portable one-pixel PNG replaces irrelevant team logo downloads."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff\xff"))
            + chunk(b"IEND", b""))


def assert_value(expression, expected):
    return (
        f"    actual = {expression}\n"
        f"    expected = {literal(expected)}\n"
        "    if actual != expected:\n"
        "        fail(\"expected\", expected, \"got\", actual)\n"
        "    print(\"TEST_VALUE:\" + json.encode(actual))\n"
        "    return render.Root(child = render.Box())\n"
    )


class DeviceTimezoneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PIXLET:
            raise RuntimeError("Pixlet is required; install it or set PIXLET=/path/to/pixlet")

    @classmethod
    def tearDownClass(cls):
        destination = os.environ.get("TIMEZONE_TEST_RESULTS")
        if destination:
            evidence = {
                "pixlet_version": subprocess.check_output([PIXLET, "version"], text=True).strip(),
                "fixture_count": len(RESULTS), "fixtures": RESULTS,
                "limits": "Offline Starlark fixtures; no live provider, deployment, or physical screen verification.",
            }
            Path(destination).write_text(json.dumps(evidence, indent=2) + "\n")

    def fixture(self, source_path, *, timezone=PHOENIX, now="2026-07-01T18:00:00Z",
                responses=None, config=None, body=None, edit=None, name=None):
        responses = responses or {}
        original = source_path.read_text()
        source = original
        self.assertEqual(source.count("def main(config):"), 1)
        source = source.replace("def main(config):", "def app_main(config):", 1)
        for module in ("http", "time"):
            old = f'load("{module}.star", "{module}")'
            self.assertEqual(source.count(old), 1)
            source = source.replace(old, f'load("fixture_{module}.star", "{module}")', 1)
        if 'load("encoding/json.star", "json")' not in source:
            source = 'load("encoding/json.star", "json")\n' + source
        if edit:
            source = edit(source)
        source += "\n\ndef main(config):\n"
        source += "    if time.tz() != " + json.dumps(timezone) + ":\n"
        source += "        fail(\"fixture device timezone did not reach Pixlet\", time.tz())\n"
        source += body or "    return app_main(config)\n"
        serialized = {url: [status, payload if isinstance(payload, str) else json.dumps(payload)]
                      for url, (status, payload) in responses.items()}
        http_module = '''load("encoding/json.star", "json")
load("pixel.png", PIXEL = "file")
RESPONSES = %s

def fixture_get(url, ttl_seconds = 0):
    print("TEST_REQUEST:" + url)
    if url not in RESPONSES:
        fail("unexpected HTTP request; fixture has no network access", url)
    response = RESPONSES[url]
    payload = PIXEL.readall() if response[1] == "FIXTURE_PNG" else response[1]
    return struct(status_code = response[0], body = lambda: payload,
                  json = lambda: json.decode(payload))

http = struct(get = fixture_get)
''' % literal(serialized)
        time_module = '''load("time.star", real_time = "time")
MOCK_NOW = %s

def fixture_now(location = None):
    moment = real_time.parse_time(MOCK_NOW)
    return moment.in_location(location if location != None else real_time.tz())

time = struct(now = fixture_now, tz = real_time.tz,
              parse_time = real_time.parse_time, parse_duration = real_time.parse_duration,
              time = real_time.time, is_valid_timezone = real_time.is_valid_timezone,
              hour = real_time.hour, minute = real_time.minute)
''' % json.dumps(now)
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="pixlet-timezone-test-") as temp:
            folder = Path(temp)
            assets = source_path.parent / "images"
            if assets.exists():
                shutil.copytree(assets, folder / "images")
            (folder / "app.star").write_text(source)
            (folder / "fixture_http.star").write_text(http_module)
            (folder / "fixture_time.star").write_text(time_module)
            (folder / "pixel.png").write_bytes(placeholder_png())
            (folder / "config.json").write_text(json.dumps(config or {}))
            output = folder / "result.webp"
            result = subprocess.run(
                [PIXLET, "render", str(folder), "--config", str(folder / "config.json"),
                 "--output", str(output), "--timeout", "10s"],
                capture_output=True, text=True, timeout=20, env={**os.environ, "TZ": timezone},
            )
            log = result.stdout + result.stderr
            requests = [line.split("TEST_REQUEST:", 1)[1] for line in log.splitlines()
                        if "TEST_REQUEST:" in line]
            RESULTS.append({
                "test": name or self.id(), "source": str(source_path.relative_to(ROOT)),
                "sha256": hashlib.sha256(original.encode()).hexdigest(), "mock_now": now,
                "device_timezone": timezone, "returncode": result.returncode,
                "requests": requests, "expected_requests": list(responses),
                "rendered": output.exists(), "output": log.strip(),
                "elapsed_seconds": round(time.monotonic() - started, 3),
            })
            self.assertEqual(result.returncode, 0, log)
            self.assertTrue(output.exists(), log)
            self.assertEqual(requests, list(responses), "missing or unexpected fixture requests")

    def game_fixture(self, timezone, now, date, start=None, expected=None):
        games = []
        if start:
            games = [{"gameDate": start, "gameType": "R", "gamePk": 1,
                      "status": {"abstractGameState": "Preview"},
                      "linescore": {"currentInning": 0},
                      "teams": {"home": {"team": {"id": 119, "abbreviation": "LAD"}},
                                "away": {"team": {"id": 111, "abbreviation": "BOS"}}}}]
        self.fixture(GAME, timezone=timezone, now=now,
                     config={**stale_settings(timezone), "team": "LAD"}, responses={
                         ESPN + "?limit=100": (200, {"events": []}),
                         MLB + "/teams?sportId=1&activeStatus=Y": (200, {"teams": [{"id": 119}, {"id": 111}]}),
                         MLB + "/schedule?sportId=1&teamId=119&hydrate=linescore&date=" + date:
                             (200, {"dates": [{"games": games}]}),
                     }, body=assert_value('get_game_data(config)["start_text"]' if start else
                                          'get_game_data(config)["fetch_ok"]', expected if start else True),
                     name=f"game_{timezone}_{now}_{start or 'schedule'}")

    def test_game_summer_winter_uses_device_zone_and_ignores_saved_timezone(self):
        for zone, summer, winter in [(PHOENIX, "4:05 MST", "4:05 MST"),
                                    (EASTERN, "7:05 EDT", "6:05 EST")]:
            for date, expected in [("2026-07-01", summer), ("2026-01-01", winter)]:
                with self.subTest(zone=zone, date=date):
                    self.game_fixture(zone, date + "T18:00:00Z", date, date + "T23:05:00Z", expected)

    def test_game_dst_boundaries_use_timestamp_abbreviation(self):
        dates = ["2026-03-08T06:59:00Z", "2026-03-08T07:00:00Z",
                 "2026-11-01T05:59:00Z", "2026-11-01T06:00:00Z"]
        for zone, expected in [(PHOENIX, ["11:59 MST", "12:00 MST", "10:59 MST", "11:00 MST"]),
                               (EASTERN, ["1:59 EST", "3:00 EDT", "1:59 EDT", "1:00 EST"])]:
            with self.subTest(zone=zone):
                self.fixture(GAME, timezone=zone,
                             body=assert_value("[format_start_text(date) for date in %s]" % literal(dates), expected))

    def test_game_schedule_date_follows_each_device_at_year_and_day_rollover(self):
        for now, phoenix, eastern in [("2027-01-01T06:30:00Z", "2026-12-31", "2027-01-01"),
                                      ("2027-01-01T07:00:00Z", "2027-01-01", "2027-01-01"),
                                      ("2026-07-02T05:30:00Z", "2026-07-01", "2026-07-02")]:
            for zone, date in [(PHOENIX, phoenix), (EASTERN, eastern)]:
                with self.subTest(zone=zone, now=now):
                    self.game_fixture(zone, now, date)

    def test_leaders_season_year_follows_each_device(self):
        for now, phoenix, eastern in [("2027-01-01T06:30:00Z", 2026, 2027),
                                      ("2027-01-01T07:00:00Z", 2027, 2027)]:
            for zone, year in [(PHOENIX, phoenix), (EASTERN, eastern)]:
                with self.subTest(zone=zone, now=now):
                    self.fixture(LEADERS, timezone=zone, now=now, config=stale_settings(zone), responses={
                        MLB + f"/stats/leaders?sportId=1&leaderCategories=homeRuns&season={year}&hydrate=team&limit=5":
                            (200, {"leagueLeaders": []}),
                    }, body=assert_value('get_leaders("homeRuns")', ["No Stats!!"]),
                        name=f"leaders_{zone}_{now}")

    def test_scores_schedule_window_uses_device_date_despite_stale_location(self):
        for zone, day in [(PHOENIX, datetime(2026, 12, 31)), (EASTERN, datetime(2027, 1, 1))]:
            for team in ["all", "LAD"]:
                if team == "all":
                    responses = {ESPN + "?limit=100&dates=" + day.strftime("%Y%m%d"): (200, {"events": []})}
                else:
                    responses = {ESPN + "?dates=" + (day + timedelta(days=d)).strftime("%Y%m%d"):
                                 (200, {"events": []}) for d in range(-1, 7)}
                with self.subTest(zone=zone, team=team):
                    self.fixture(SCORES, timezone=zone, now="2027-01-01T06:30:00Z",
                                 config={**stale_settings(zone), "selectedTeam": team}, responses=responses,
                                 body=assert_value("app_main(config)", []), name=f"scores_schedule_{zone}_{team}")

    def test_scores_selected_team_window_uses_calendar_days_across_dst_and_leap_day(self):
        cases = [
            ("spring_dst", "2026-03-09T04:30:00Z", datetime(2026, 3, 9)),
            ("fall_dst", "2026-10-31T04:30:00Z", datetime(2026, 10, 31)),
            ("leap_day", "2028-02-29T05:30:00Z", datetime(2028, 2, 29)),
        ]
        for label, now, local_day in cases:
            # A calendar sequence is the expected contract, regardless of the
            # number of elapsed hours between local midnights.
            dates = [(local_day + timedelta(days=d)).strftime("%Y%m%d") for d in range(-1, 7)]
            responses = {ESPN + "?dates=" + date: (200, {"events": []}) for date in dates}
            self.assertEqual(len(responses), 8)
            with self.subTest(case=label):
                self.fixture(SCORES, timezone=EASTERN, now=now,
                             config={**stale_settings(EASTERN), "selectedTeam": "LAD"},
                             responses=responses, body=assert_value("app_main(config)", []),
                             name=f"scores_calendar_window_{label}")

    def scores_fixture(self, zone, now, start, date, expected):
        event = {"date": start, "status": {"type": {"state": "pre"}}, "competitions": [{
            "competitors": [{"team": {"abbreviation": team, "shortDisplayName": team,
                                        "logo": f"https://fixture.invalid/{team}.png"}}
                            for team in ["AAA", "BBB"]]}]}
        responses = {ESPN + "?limit=100&dates=" + date: (200, {"events": [event]})}
        responses.update({f"https://fixture.invalid/{team}.png&h=50&w=50": (200, "FIXTURE_PNG")
                          for team in ["AAA", "BBB"]})

        def instrument(source):
            signature = "def get_date_column(displayTop, now, scoreNumber, rotationSpeed, textColor, borderColor, displayType, gameTime, timeColor):\n"
            self.assertEqual(source.count(signature), 1)
            check = ("    if gameTime != " + json.dumps(expected) + ":\n"
                     "        fail(\"incorrect score time/date text\", gameTime)\n"
                     "    print(\"TEST_VALUE:\" + gameTime)\n")
            return source.replace(signature, signature + check, 1)

        self.fixture(SCORES, timezone=zone, now=now,
                     config={**stale_settings(zone), "displayTop": "gameinfo"},
                     responses=responses, edit=instrument, name=f"scores_{zone}_{now}_{start}")

    def test_scores_summer_winter_ignore_saved_location(self):
        for zone, summer, winter in [(PHOENIX, "4:05 PM", "4:05 PM"),
                                    (EASTERN, "7:05 PM", "6:05 PM")]:
            for date, expected in [("2026-07-01", summer), ("2026-01-01", winter)]:
                with self.subTest(zone=zone, date=date):
                    self.scores_fixture(zone, date + "T18:00:00Z", date + "T23:05Z", date.replace("-", ""), expected)

    def test_scores_midnight_and_full_year_date_comparison(self):
        cases = [
            (PHOENIX, "2026-07-02T06:30:00Z", "2026-07-02T06:45Z", "20260701", "11:45 PM"),
            (EASTERN, "2026-07-02T06:30:00Z", "2026-07-02T06:45Z", "20260702", "2:45 AM"),
            (PHOENIX, "2026-07-02T06:30:00Z", "2026-07-02T07:05Z", "20260701", "Jul 2"),
            (EASTERN, "2026-07-02T06:30:00Z", "2026-07-02T07:05Z", "20260702", "3:05 AM"),
            (PHOENIX, "2027-01-01T06:30:00Z", "2025-12-31T23:05Z", "20261231", "Dec 31"),
            (EASTERN, "2027-01-01T06:30:00Z", "2026-01-01T23:05Z", "20270101", "Jan 1"),
        ]
        for zone, now, start, date, expected in cases:
            with self.subTest(zone=zone, now=now, start=start):
                self.scores_fixture(zone, now, start, date, expected)

    def national_fixture(self, zone, now, route, label, status=200, qr=False, empty=False):
        url = "https://nationaltoday.com/" + route + "/"
        # Real dated pages lack the date metadata consumed by the previous app.
        html = "<html><title>Dated holidays</title>"
        if not empty:
            html += '<a class="holiday-title">Fixture Holiday</a>'
        html += "</html>"
        expected = [label, "No holidays today :(" if empty else "Fixture Holiday"]
        if status != 200:
            expected = ["Error", "Could not get holidays!!!!"]

        def instrument(source):
            marker = '    if config.bool("qrcode", False):\n'
            self.assertEqual(source.count(marker), 1)
            check = (f"    if holiday_txt != {literal(expected)}:\n"
                     "        fail(\"incorrect holiday date/error text\", holiday_txt)\n"
                     "    print(\"TEST_VALUE:\" + json.encode(holiday_txt))\n")
            source = source.replace(marker, check + marker, 1)
            if qr:
                source = source.replace('load("qrcode.star", "qrcode")',
                                        'load("qrcode.star", real_qrcode = "qrcode")', 1)
                source += '''
def fixture_generate(url, size, color, background):
    if url != %s:
        fail("QR points to a different day", url)
    print("TEST_QR:" + url)
    return real_qrcode.generate(url = url, size = size, color = color, background = background)

qrcode = struct(generate = fixture_generate)
''' % json.dumps(url)
            return source

        self.fixture(HOLIDAYS, timezone=zone, now=now, responses={url: (status, html)},
                     config={**stale_settings(zone), "qrcode": "true" if qr else "false"}, edit=instrument,
                     name=f"holidays_{zone}_{now}_{status}_qr{qr}_empty{empty}")
        if qr:
            self.assertIn("TEST_QR:" + url, RESULTS[-1]["output"])

    def test_nationaltoday_date_label_and_qr_follow_device_despite_stale_config(self):
        cases = [
            ("2026-07-02T05:30:00Z", PHOENIX, "july-1", "July 1, 2026"),
            ("2026-07-02T05:30:00Z", EASTERN, "july-2", "July 2, 2026"),
            ("2027-01-01T06:30:00Z", PHOENIX, "december-31", "Dec 31, 2026"),
            ("2027-01-01T06:30:00Z", EASTERN, "january-1", "Jan 1, 2027"),
            ("2027-01-01T07:00:00Z", PHOENIX, "january-1", "Jan 1, 2027"),
        ]
        for now, zone, route, label in cases:
            with self.subTest(zone=zone, now=now):
                self.national_fixture(zone, now, route, label, qr=True)

    def test_nationaltoday_errors_never_fallback_to_provider_today(self):
        for zone, route, label in [(PHOENIX, "october-14", "Oct 14, 2026"),
                                   (EASTERN, "october-15", "Oct 15, 2026")]:
            for status in [404, 503]:
                with self.subTest(zone=zone, status=status):
                    self.national_fixture(zone, "2026-10-15T06:30:00Z", route, label, status=status)

    def test_nationaltoday_empty_page_preserves_device_date(self):
        self.national_fixture(PHOENIX, "2026-10-15T06:30:00Z", "october-14", "Oct 14, 2026", empty=True)


if __name__ == "__main__":
    unittest.main()
