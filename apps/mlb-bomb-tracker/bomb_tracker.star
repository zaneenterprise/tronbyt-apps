load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

SEASON_URL = "https://statsapi.mlb.com/api/v1/seasons/current?sportId=1"
PLAYERS_URL = "https://statsapi.mlb.com/api/v1/sports/1/players?season=%s&fields=people,id,fullName,currentTeam,id"
TEAMS_URL = "https://statsapi.mlb.com/api/v1/teams?sportId=1&season=%s&fields=teams,id,name,abbreviation,teamName,clubName"
PLAYER_STATS_URL = "https://statsapi.mlb.com/api/v1/people/%s/stats?stats=season&group=hitting&season=%s&gameType=%s"
TEAM_STATS_URL = "https://statsapi.mlb.com/api/v1/teams/%s/stats?stats=season&group=hitting&season=%s&gameType=%s"
HEADSHOT_URL = "https://img.mlbstatic.com/mlb-photos/image/upload/d_people:generic:headshot:silo:current.png/w_213,q_auto:best/v1/people/%s/headshot/silo/current"
TEAM_LOGO_URL = "https://www.mlbstatic.com/team-logos/team-cap-on-dark/%s.svg"

SEASON_TTL = 21600
DIRECTORY_TTL = 21600
STATS_TTL = 300
ART_TTL = 86400
MAX_RESULTS = 10

BACKGROUND = "#07131f"
CARD = "#112033"
TEXT = "#f5f7fa"
MUTED = "#9eb3c7"
COUNT = "#ffd166"
ACCENT = "#ff6b35"

POSTSEASON_ROUNDS = ["D", "L", "W"]
BOMB_ICON = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <circle cx="7.5" cy="10.5" r="5.5" fill="#1f242b" stroke="#4f5863" stroke-width="1"/>
  <circle cx="5.5" cy="8.4" r="1.5" fill="#6d7681" opacity="0.8"/>
  <path d="M11.3 5.9L13.0 4.1c.4-.4 1-.4 1.4 0l.3.3c.4.4.4 1 0 1.4l-1.8 1.8" fill="none" stroke="#8b5e34" stroke-width="1.2" stroke-linecap="round"/>
  <path d="M14.8 4.4l1.4-1.1M15.2 5.1l1.9-.2M14.7 5.3l1.4 1.4" fill="none" stroke="#ffb703" stroke-width="1.1" stroke-linecap="round"/>
</svg>
"""

def main(config):
    return run_app(config)

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            subject_field(),
        ],
    )

def subject_field():
    return schema.Typeahead(
        id = "player",
        name = "Player or Team",
        desc = "Type an MLB player or team name and pick the match to track.",
        icon = "baseball",
        handler = search_live_subjects,
    )

def search_live_subjects(pattern):
    season_info = get_season_info()
    if season_info == None:
        return []
    return search_subjects(pattern, season_info["season"])

def run_app(config):
    selection_raw = config.get("player", "")
    if selection_raw == "":
        return render_message_state(
            title = "Select",
            subtitle = "player/team",
            note = "in settings",
        )

    selection = decode_selection(selection_raw)
    if selection == None:
        return render_error_state("BAD CFG")

    runtime = get_runtime()
    if runtime.get("error", "") != "":
        return render_error_state(runtime["error"])

    stats = get_subject_stats(selection, runtime["season"], runtime["game_type"])
    if stats == None:
        return render_error_state("API ERR")

    art = get_subject_art(selection)
    return render_subject_card(
        subject_name = selection["name"],
        season = runtime["season"],
        game_type = runtime["game_type"],
        home_runs = format_home_runs(stats["homeRuns"]),
        art = art,
        subject_kind = selection["kind"],
    )

def get_runtime():
    season_info = get_season_info()
    if season_info == None:
        return {"error": "API ERR"}
    return season_info

def search_subjects(pattern, season):
    normalized = (pattern or "").strip().lower()
    if normalized == "":
        return []

    exact_matches = []
    prefix_matches = []
    contains_matches = []

    for subject in get_subject_directory(season):
        match_type = classify_subject_match(subject, normalized)
        if match_type == "exact":
            exact_matches.append(subject)
        elif match_type == "prefix":
            prefix_matches.append(subject)
        elif match_type == "contains":
            contains_matches.append(subject)

    options = []
    append_subject_options(options, exact_matches)
    append_subject_options(options, prefix_matches)
    append_subject_options(options, contains_matches)

    return options

def classify_subject_match(subject, normalized):
    for term in subject["terms"]:
        if term == normalized:
            return "exact"

    for term in subject["terms"]:
        if term.startswith(normalized):
            return "prefix"

    haystack = subject["search"]
    if normalized in haystack:
        return "contains"

    return ""

def append_subject_options(options, subjects):
    for kind in ["team", "player"]:
        for subject in subjects:
            if len(options) >= MAX_RESULTS:
                return
            if subject["kind"] == kind:
                options.append(subject_option(subject))

def subject_option(subject):
    return schema.Option(
        display = subject["display"],
        value = "%s:%s" % (subject["kind"], subject["id"]),
    )

def decode_selection(selection_raw):
    option = json.decode(selection_raw, None)
    if option == None or type(option) != "dict":
        return None

    subject_ref = decode_subject_ref(option.get("value", ""))
    if subject_ref == None:
        return None

    display = str(option.get("display", "")).strip()
    subject_name = display_name(display)
    if subject_name == "":
        subject_name = "MLB %s" % subject_ref["kind"].title()

    return {
        "kind": subject_ref["kind"],
        "id": subject_ref["id"],
        "name": subject_name,
    }

def decode_subject_ref(raw_value):
    raw = str(raw_value).strip()
    if raw == "":
        return None

    if ":" not in raw:
        subject_id = normalize_numeric_id(raw)
        if subject_id == "":
            return None
        return {
            "kind": "player",
            "id": subject_id,
        }

    parts = raw.split(":")
    if len(parts) != 2:
        return None

    kind = parts[0].strip()
    subject_id = normalize_numeric_id(parts[1])
    if subject_id == "":
        return None
    if kind != "player" and kind != "team":
        return None

    return {
        "kind": kind,
        "id": subject_id,
    }

def normalize_numeric_id(raw_id):
    raw = str(raw_id).strip()
    if raw == "":
        return ""

    if raw.endswith(".0"):
        return raw[:-2]

    parts = raw.split(".")
    if len(parts) != 2:
        return raw

    whole = parts[0]
    fraction = parts[1]
    if whole == "" or fraction == "":
        return raw

    for idx in range(len(fraction)):
        if fraction[idx] != "0":
            return raw

    return whole

def get_season_info():
    response = http.get(SEASON_URL, ttl_seconds = SEASON_TTL)
    if response.status_code != 200:
        print("season lookup failed: %d" % response.status_code)
        return None

    payload = response.json()
    seasons = payload.get("seasons", [])
    if len(seasons) == 0:
        return None

    season = seasons[0]
    season_id = season.get("seasonId", None)
    regular_season_start = season.get("regularSeasonStartDate", "")
    post_season_start = season.get("postSeasonStartDate", "")
    if season_id == None or regular_season_start == "":
        return None

    return {
        "season": str(season_id),
        "game_type": infer_game_type(regular_season_start, post_season_start),
        "error": "",
    }

def infer_game_type(regular_season_start, post_season_start):
    today = time.now().format("2006-01-02")
    if today < regular_season_start:
        return "S"
    if post_season_start != "" and today >= post_season_start:
        return "P"
    return "R"

def get_subject_directory(season):
    teams = get_team_directory(season)
    team_names = {}
    for team in teams:
        team_names[team["id"]] = team["name"]

    subjects = []
    for player in get_player_directory(season, team_names):
        subjects.append(player)
    for team in teams:
        subjects.append(team)

    return subjects

def get_player_directory(season, team_names):
    response = http.get(PLAYERS_URL % season, ttl_seconds = DIRECTORY_TTL)
    if response.status_code != 200:
        print("player directory failed: %d" % response.status_code)
        return []

    payload = response.json()
    people = payload.get("people", [])
    players = []

    for person in people:
        player_id = normalize_numeric_id(person.get("id", None))
        full_name = person.get("fullName", "")
        if player_id == "" or full_name == "":
            continue

        current_team = person.get("currentTeam", {})
        team_id = ""
        if type(current_team) == "dict":
            team_id = normalize_numeric_id(current_team.get("id", None))
        team_name = team_names.get(team_id, "")
        display = full_name
        if team_name != "":
            display = "%s • %s" % (full_name, team_name)

        players.append({
            "kind": "player",
            "id": player_id,
            "display": display,
            "terms": build_search_terms([full_name, team_name]),
            "search": ("%s %s" % (full_name, team_name)).lower(),
        })

    return players

def get_team_directory(season):
    response = http.get(TEAMS_URL % season, ttl_seconds = DIRECTORY_TTL)
    if response.status_code != 200:
        print("team lookup failed: %d" % response.status_code)
        return []

    payload = response.json()
    teams = []

    for team in payload.get("teams", []):
        team_id = normalize_numeric_id(team.get("id", None))
        name = team.get("name", "")
        if team_id == "" or name == "":
            continue

        abbreviation = team.get("abbreviation", "")
        team_name = team.get("teamName", "")
        club_name = team.get("clubName", "")
        search = join_search_terms([
            name,
            abbreviation,
            team_name,
            club_name,
        ])

        teams.append({
            "kind": "team",
            "id": team_id,
            "name": name,
            "display": "%s • Team" % name,
            "terms": build_search_terms([name, abbreviation, team_name, club_name]),
            "search": search,
        })

    return teams

def get_subject_stats(selection, season, game_type):
    if game_type == "P":
        return get_postseason_stats(selection["kind"], selection["id"], season)
    return get_subject_stats_for_game_type(selection["kind"], selection["id"], season, game_type)

def get_postseason_stats(kind, subject_id, season):
    total = get_subject_stats_for_game_type(kind, subject_id, season, "P")
    if total == None:
        return None
    if total["found"]:
        return {"homeRuns": total["homeRuns"]}

    round_total = 0
    for round_type in POSTSEASON_ROUNDS:
        result = get_subject_stats_for_game_type(kind, subject_id, season, round_type)
        if result == None:
            return None
        round_total += result["homeRuns"]

    return {"homeRuns": round_total}

def get_subject_stats_for_game_type(kind, subject_id, season, game_type):
    if kind == "team":
        return get_stats_from_url(
            TEAM_STATS_URL % (subject_id, season, game_type),
            "team stats",
        )
    return get_stats_from_url(
        PLAYER_STATS_URL % (subject_id, season, game_type),
        "player stats",
    )

def get_stats_from_url(url, label):
    response = http.get(url, ttl_seconds = STATS_TTL)
    if response.status_code != 200:
        print("%s lookup failed: %d" % (label, response.status_code))
        return None

    payload = response.json()
    stats_groups = payload.get("stats", [])
    if len(stats_groups) == 0:
        return {
            "homeRuns": 0,
            "found": False,
        }

    splits = stats_groups[0].get("splits", [])
    if len(splits) == 0:
        return {
            "homeRuns": 0,
            "found": True,
        }

    stat_line = splits[0].get("stat", {})
    return {
        "homeRuns": int(stat_line.get("homeRuns", 0)),
        "found": True,
    }

def get_subject_art(selection):
    if selection["kind"] == "team":
        return get_team_logo(selection["id"])
    return get_headshot(selection["id"])

def get_headshot(player_id):
    response = http.get(HEADSHOT_URL % player_id, ttl_seconds = ART_TTL)
    if response.status_code != 200:
        print("headshot lookup failed: %d" % response.status_code)
        return None

    return response.body()

def get_team_logo(team_id):
    response = http.get(TEAM_LOGO_URL % team_id, ttl_seconds = ART_TTL)
    if response.status_code != 200:
        print("team logo lookup failed: %d" % response.status_code)
        return None

    return response.body()

def display_name(display):
    separator = " • "
    if separator in display:
        return display.split(separator)[0]
    return display

def render_subject_card(subject_name, season, game_type, home_runs, art, subject_kind):
    return render.Root(
        max_age = STATS_TTL,
        child = render.Box(
            color = BACKGROUND,
            child = render.Padding(
                pad = (2, 1, 1, 1),
                child = render.Column(
                    expanded = True,
                    main_align = "space_between",
                    cross_align = "start",
                    children = [
                        render_subject_name(subject_name),
                        render.Row(
                            expanded = True,
                            main_align = "space_between",
                            cross_align = "end",
                            children = [
                                render_stat_block(home_runs, season, game_type),
                                render_subject_art(art, subject_kind),
                            ],
                        ),
                    ],
                ),
            ),
        ),
    )

def render_subject_name(subject_name):
    return render.Text(
        content = subject_name,
        font = "tom-thumb",
        color = TEXT,
    )

def render_stat_block(home_runs, season, game_type):
    return render.Column(
        cross_align = "start",
        children = [
            render.Row(
                cross_align = "center",
                children = [
                    render.Image(
                        src = BOMB_ICON,
                        width = 14,
                        height = 14,
                    ),
                    render.Padding(
                        pad = (2, 0, 0, 0),
                        child = render.Text(
                            content = home_runs,
                            font = "6x13",
                            color = COUNT,
                        ),
                    ),
                ],
            ),
            render.Text(
                content = stat_label(season, game_type),
                font = "CG-pixel-3x5-mono",
                color = ACCENT,
            ),
        ],
    )

def stat_label(season, game_type):
    if game_type == "S":
        return "SPR HRs"
    if game_type == "P":
        return "PST HRs"
    return "%s HRs" % season

def format_home_runs(home_runs):
    return "%d" % int(home_runs)

def render_subject_art(art, subject_kind):
    fallback = "MLB"
    if subject_kind == "team":
        fallback = "TEAM"

    child = render.Column(
        expanded = True,
        main_align = "center",
        cross_align = "center",
        children = [
            render.Text(
                content = fallback,
                font = "CG-pixel-3x5-mono",
                color = MUTED,
            ),
        ],
    )

    if art != None:
        child = render.Column(
            expanded = True,
            main_align = "center",
            cross_align = "center",
            children = [
                render.Image(
                    src = art,
                    width = 20,
                    height = 20,
                ),
            ],
        )

    return render.Box(
        width = 23,
        height = 22,
        child = render.Box(
            width = 22,
            height = 22,
            color = CARD,
            child = child,
        ),
    )

def render_message_state(title, subtitle, note):
    return render.Root(
        child = render.Box(
            color = BACKGROUND,
            child = render.Row(
                expanded = True,
                main_align = "space_evenly",
                cross_align = "center",
                children = [
                    render.Image(src = BOMB_ICON, width = 13, height = 13),
                    render.Column(
                        cross_align = "start",
                        children = [
                            render.Text(content = title, font = "tb-8", color = COUNT),
                            render.Text(content = subtitle, font = "tb-8", color = TEXT),
                            render.Text(content = note, font = "CG-pixel-3x5-mono", color = MUTED),
                        ],
                    ),
                ],
            ),
        ),
    )

def render_error_state(message):
    return render.Root(
        child = render.Box(
            color = BACKGROUND,
            child = render.Row(
                expanded = True,
                main_align = "space_evenly",
                cross_align = "center",
                children = [
                    render.Image(src = BOMB_ICON, width = 13, height = 13),
                    render.Column(
                        cross_align = "start",
                        children = [
                            render.Text(content = "Bomb", font = "tb-8", color = COUNT),
                            render.Text(content = "Tracker", font = "tb-8", color = TEXT),
                            render.Text(content = message, font = "CG-pixel-3x5-mono", color = ACCENT),
                        ],
                    ),
                ],
            ),
        ),
    )

def join_search_terms(parts):
    values = []
    for part in parts:
        text = str(part).strip()
        if text != "":
            values.append(text)
    return " ".join(values).lower()

def build_search_terms(parts):
    terms = []
    for part in parts:
        text = str(part).strip().lower()
        if text != "":
            terms.append(text)
    return terms
