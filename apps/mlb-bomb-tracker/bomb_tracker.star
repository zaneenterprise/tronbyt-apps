load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

SEASON_URL = "https://statsapi.mlb.com/api/v1/seasons/current?sportId=1"
PLAYERS_URL = "https://statsapi.mlb.com/api/v1/sports/1/players?season=%s&fields=people,id,fullName,currentTeam,id"
TEAMS_URL = "https://statsapi.mlb.com/api/v1/teams?sportId=1&season=%s&fields=teams,id,name"
STATS_URL = "https://statsapi.mlb.com/api/v1/people/%s/stats?stats=season&group=hitting&season=%s&gameType=%s"
HEADSHOT_URL = "https://img.mlbstatic.com/mlb-photos/image/upload/d_people:generic:headshot:silo:current.png/w_213,q_auto:best/v1/people/%s/headshot/silo/current"

SEASON_TTL = 21600
DIRECTORY_TTL = 21600
STATS_TTL = 300
HEADSHOT_TTL = 86400
MAX_RESULTS = 10

BACKGROUND = "#07131f"
CARD = "#112033"
TEXT = "#f5f7fa"
MUTED = "#9eb3c7"
COUNT = "#ffd166"
ACCENT = "#ff6b35"

BOMB_ICON = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <circle cx="7.5" cy="10.5" r="5.5" fill="#1f242b" stroke="#4f5863" stroke-width="1"/>
  <circle cx="5.5" cy="8.4" r="1.5" fill="#6d7681" opacity="0.8"/>
  <path d="M11.3 5.9L13.0 4.1c.4-.4 1-.4 1.4 0l.3.3c.4.4.4 1 0 1.4l-1.8 1.8" fill="none" stroke="#8b5e34" stroke-width="1.2" stroke-linecap="round"/>
  <path d="M14.8 4.4l1.4-1.1M15.2 5.1l1.9-.2M14.7 5.3l1.4 1.4" fill="none" stroke="#ffb703" stroke-width="1.1" stroke-linecap="round"/>
</svg>
"""

def main(config):
    selection_raw = config.get("player", "")

    season_info = get_season_info()
    if selection_raw == "":
        return render_message_state(
            title = "Select",
            subtitle = "player",
            note = "in settings",
        )

    selection = decode_selection(selection_raw)
    if selection == None:
        return render_error_state("BAD CFG")

    if season_info == None:
        return render_error_state("API ERR")

    season = season_info["season"]
    game_type = season_info["game_type"]
    if game_type == "P":
        stats = get_postseason_stats(selection["id"], season)
    else:
        stats = get_player_stats(selection["id"], season, game_type)
    if stats == None:
        return render_error_state("API ERR")

    headshot = get_headshot(selection["id"])
    return render_player_card(
        player_name = selection["name"],
        season = season,
        game_type = game_type,
        home_runs = format_home_runs(stats["homeRuns"]),
        headshot = headshot,
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Typeahead(
                id = "player",
                name = "Player",
                desc = "Type an MLB player name and pick the matching hitter.",
                icon = "baseball",
                handler = search_players,
            ),
        ],
    )

def search_players(pattern):
    season_info = get_season_info()
    if season_info == None:
        return []
    season = season_info["season"]

    normalized = (pattern or "").strip().lower()
    if normalized == "":
        return []

    prefix_matches = []
    contains_matches = []

    for player in get_player_directory(season):
        haystack = player["search"]
        if haystack.startswith(normalized):
            prefix_matches.append(player)
        elif normalized in haystack:
            contains_matches.append(player)

    options = []
    for player in prefix_matches:
        if len(options) >= MAX_RESULTS:
            break
        options.append(player_option(player))

    for player in contains_matches:
        if len(options) >= MAX_RESULTS:
            break
        options.append(player_option(player))

    return options

def player_option(player):
    return schema.Option(
        display = player["display"],
        value = player["id"],
    )

def decode_selection(selection_raw):
    option = json.decode(selection_raw, None)
    if option == None or type(option) != "dict":
        return None

    player_id = normalize_player_id(option.get("value", ""))
    display = option.get("display", "")
    if player_id == "":
        return None

    return {
        "id": player_id,
        "name": display_name(display),
    }

def normalize_player_id(player_id):
    raw = str(player_id).strip()
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

    for char in fraction:
        if char != "0":
            return raw

    return whole

#this is what determines if its spring training or not. 
#it returns the regular season start date 
#and if its that day or later it shows regular season stats.
#same with postseason, it determines postseason start date
#and if it is that day or after it shows postseason stats

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
        "season": season_id,
        "game_type": infer_game_type(regular_season_start, post_season_start),
    }

def infer_game_type(regular_season_start, post_season_start):
    today = time.now().format("2006-01-02")
    if today < regular_season_start:
        return "S"
    if post_season_start != "" and today >= post_season_start:
        return "P"
    return "R"

def get_player_directory(season):
    team_names = get_team_names(season)
    response = http.get(PLAYERS_URL % season, ttl_seconds = DIRECTORY_TTL)
    if response.status_code != 200:
        print("player directory failed: %d" % response.status_code)
        return []

    payload = response.json()
    people = payload.get("people", [])
    players = []

    for person in people:
        player_id = person.get("id", None)
        full_name = person.get("fullName", "")
        if player_id == None or full_name == "":
            continue

        current_team = person.get("currentTeam", {})
        team_id = current_team.get("id", None) if type(current_team) == "dict" else None
        team_name = team_names.get(team_id, "")
        display = full_name
        if team_name != "":
            display = "%s • %s" % (full_name, team_name)

        players.append({
            "id": str(player_id),
            "display": display,
            "search": ("%s %s" % (full_name, team_name)).lower(),
        })

    return players

def get_team_names(season):
    response = http.get(TEAMS_URL % season, ttl_seconds = DIRECTORY_TTL)
    if response.status_code != 200:
        print("team lookup failed: %d" % response.status_code)
        return {}

    payload = response.json()
    names = {}

    for team in payload.get("teams", []):
        team_id = team.get("id", None)
        if team_id != None:
            names[team_id] = team.get("name", "")

    return names

def get_player_stats(player_id, season, game_type):
    response = http.get(STATS_URL % (player_id, season, game_type), ttl_seconds = STATS_TTL)
    if response.status_code != 200:
        print("stats lookup failed: %d" % response.status_code)
        return None

    payload = response.json()
    stats_groups = payload.get("stats", [])
    if len(stats_groups) == 0:
        return {"homeRuns": 0}

    splits = stats_groups[0].get("splits", [])
    if len(splits) == 0:
        return {"homeRuns": 0}

    stat_line = splits[0].get("stat", {})
    return {
        "homeRuns": int(stat_line.get("homeRuns", 0)),
    }

def get_postseason_stats(player_id, season):
    total = 0
    for round_type in ["P", "D", "L", "W"]:
        result = get_player_stats(player_id, season, round_type)
        if result != None:
            total += result["homeRuns"]
    return {"homeRuns": total}

def get_headshot(player_id):
    response = http.get(HEADSHOT_URL % player_id, ttl_seconds = HEADSHOT_TTL)
    if response.status_code != 200:
        print("headshot lookup failed: %d" % response.status_code)
        return None

    return response.body()

def display_name(display):
    separator = " • "
    if separator in display:
        return display.split(separator)[0]
    return display

def render_player_card(player_name, season, game_type, home_runs, headshot):
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
                        render_player_name(player_name),
                        render.Row(
                            expanded = True,
                            main_align = "space_between",
                            cross_align = "end",
                            children = [
                                render_stat_block(home_runs, season, game_type),
                                render_headshot(headshot),
                            ],
                        ),
                    ],
                ),
            ),
        ),
    )

def render_player_name(player_name):
    return render.Text(
        content = player_name,
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

def render_headshot(headshot):
    child = render.Column(
        main_align = "center",
        cross_align = "center",
        children = [
            render.Text(
                content = "MLB",
                font = "CG-pixel-3x5-mono",
                color = MUTED,
            ),
        ],
    )

    if headshot != None:
        child = render.Image(
            src = headshot,
            width = 20,
            height = 20,
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
