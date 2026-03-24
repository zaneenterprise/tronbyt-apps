load("encoding/json.star", "json")
load("http.star", "http")
load("humanize.star", "humanize")
load("images/tail_aa.png", TAIL_AA_ASSET = "file")
load("images/tail_ay.png", TAIL_AY_ASSET = "file")
load("images/tail_b6.png", TAIL_B6_ASSET = "file")
load("images/tail_ba.png", TAIL_BA_ASSET = "file")
load("images/tail_cx.png", TAIL_CX_ASSET = "file")
load("images/tail_dl.png", TAIL_DL_ASSET = "file")
load("images/tail_ek.png", TAIL_EK_ASSET = "file")
load("images/tail_ey.png", TAIL_EY_ASSET = "file")
load("images/tail_fz.png", TAIL_FZ_ASSET = "file")
load("images/tail_ib.png", TAIL_IB_ASSET = "file")
load("images/tail_ix.png", TAIL_IX_ASSET = "file")
load("images/tail_jl.png", TAIL_JL_ASSET = "file")
load("images/tail_km.png", TAIL_KM_ASSET = "file")
load("images/tail_la.png", TAIL_LA_ASSET = "file")
load("images/tail_mh.png", TAIL_MH_ASSET = "file")
load("images/tail_ms.png", TAIL_MS_ASSET = "file")
load("images/tail_oz.png", TAIL_OZ_ASSET = "file")
load("images/tail_pr.png", TAIL_PR_ASSET = "file")
load("images/tail_q4.png", TAIL_Q4_ASSET = "file")
load("images/tail_qf.png", TAIL_QF_ASSET = "file")
load("images/tail_qr.png", TAIL_QR_ASSET = "file")
load("images/tail_rj.png", TAIL_RJ_ASSET = "file")
load("images/tail_sk.png", TAIL_SK_ASSET = "file")
load("images/tail_sq.png", TAIL_SQ_ASSET = "file")
load("images/tail_tg.png", TAIL_TG_ASSET = "file")
load("images/tail_tk.png", TAIL_TK_ASSET = "file")
load("images/tail_u2.png", TAIL_U2_ASSET = "file")
load("images/tail_ua.png", TAIL_UA_ASSET = "file")
load("images/tail_ul.png", TAIL_UL_ASSET = "file")
load("images/tail_wy.png", TAIL_WY_ASSET = "file")
load("math.star", "math")
load("render.star", "render")
load("schema.star", "schema")

DEFAULT_LOCATION = json.encode({
    "lat": "51.4395598",
    "lng": "-0.1013327",
    "description": "London Bridge, London, UK",
    "locality": "London",
    "place_id": "",
    "timezone": "",
})
DEFAULT_DISTANCE = "3"
DEFAULT_CACHE = 180
ADSB_POINT_URL = "https://api.adsb.lol/v2/point"
ADSB_ROUTE_URL = "https://api.adsb.lol/api/0/route"
ROUTE_DATA_URL = "https://vrs-standing-data.adsb.lol/routes"
MILES_TO_NAUTICAL_MILES = 0.868976
KNOTS_TO_MPH = 1.150779448
NAUTICAL_MILES_TO_MILES = 1.150779448
MAX_ROUTE_LOOKUPS = 8
CARDINAL_POINTS = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest", "North"]
COMPACT_CARDINAL_POINTS = {
    "North": "N",
    "Northeast": "NE",
    "East": "E",
    "Southeast": "SE",
    "South": "S",
    "Southwest": "SW",
    "West": "W",
    "Northwest": "NW",
}
TAILS = {
    "AA": TAIL_AA_ASSET.readall(),
    "AY": TAIL_AY_ASSET.readall(),
    "B6": TAIL_B6_ASSET.readall(),
    "BA": TAIL_BA_ASSET.readall(),
    "CX": TAIL_CX_ASSET.readall(),
    "DL": TAIL_DL_ASSET.readall(),
    "EK": TAIL_EK_ASSET.readall(),
    "EY": TAIL_EY_ASSET.readall(),
    "FZ": TAIL_FZ_ASSET.readall(),
    "IB": TAIL_IB_ASSET.readall(),
    "IX": TAIL_IX_ASSET.readall(),
    "JL": TAIL_JL_ASSET.readall(),
    "KM": TAIL_KM_ASSET.readall(),
    "LA": TAIL_LA_ASSET.readall(),
    "MH": TAIL_MH_ASSET.readall(),
    "MS": TAIL_MS_ASSET.readall(),
    "OZ": TAIL_OZ_ASSET.readall(),
    "PR": TAIL_PR_ASSET.readall(),
    "QF": TAIL_QF_ASSET.readall(),
    "QR": TAIL_QR_ASSET.readall(),
    "Q4": TAIL_Q4_ASSET.readall(),
    "RJ": TAIL_RJ_ASSET.readall(),
    "SK": TAIL_SK_ASSET.readall(),
    "SQ": TAIL_SQ_ASSET.readall(),
    "TG": TAIL_TG_ASSET.readall(),
    "TK": TAIL_TK_ASSET.readall(),
    "U2": TAIL_U2_ASSET.readall(),
    "UA": TAIL_UA_ASSET.readall(),
    "UL": TAIL_UL_ASSET.readall(),
    "WY": TAIL_WY_ASSET.readall(),
}
ICAO_TO_TAIL_KEY = {
    "AAL": "AA",
    "FIN": "AY",
    "JBU": "B6",
    "BAW": "BA",
    "CPA": "CX",
    "DAL": "DL",
    "UAE": "EK",
    "ETD": "EY",
    "FDB": "FZ",
    "IBE": "IB",
    "AXB": "IX",
    "JAL": "JL",
    "AMC": "KM",
    "LAN": "LA",
    "TAM": "LA",
    "MAS": "MH",
    "MSR": "MS",
    "AAR": "OZ",
    "PAL": "PR",
    "QFA": "QF",
    "QTR": "QR",
    "RJA": "RJ",
    "SAS": "SK",
    "SIA": "SQ",
    "THA": "TG",
    "THY": "TK",
    "EZY": "U2",
    "UAL": "UA",
    "ALK": "UL",
    "OMA": "WY",
}

def is_number(value):
    return type(value) == "int" or type(value) == "float"

def round_int(value):
    return int(math.round(value))

def clamp(value, minimum, maximum):
    if value < minimum:
        return minimum
    if value > maximum:
        return maximum
    return value

def safe_text(value):
    if value == None:
        return ""
    return str(value).strip()

def reduce_accuracy(coord):
    coord = safe_text(coord)
    if "." not in coord:
        return coord
    coord_list = coord.split(".")
    coord_remainder = coord_list[1]
    if len(coord_remainder) > 3:
        coord_remainder = coord_remainder[0:3]
    return ".".join([coord_list[0], coord_remainder])

def update_display(tail, text):
    return render.Row(
        children = [
            render.Box(
                width = 28,
                child = render.Image(tail),
            ),
            render.Box(
                child = render.Column(
                    children = text,
                ),
            ),
        ],
    )

def get_bearing(lat_1, lng_1, lat_2, lng_2):
    lat_1 = math.radians(float(lat_1))
    lat_2 = math.radians(float(lat_2))
    lng_1 = math.radians(float(lng_1))
    lng_2 = math.radians(float(lng_2))

    x = math.cos(lat_2) * math.sin((lng_2 - lng_1))
    y = math.cos(lat_1) * math.sin(lat_2) - math.sin(lat_1) * math.cos(lat_2) * math.cos((lng_2 - lng_1))
    bearing = math.degrees(math.atan2(x, y))

    if bearing < 0:
        bearing = 360 + bearing

    return get_cardinal_point(bearing)

def get_cardinal_point(deg, compact = False):
    if not is_number(deg):
        if compact:
            return ""
        return "Unknown"
    cardinal_point = CARDINAL_POINTS[int(math.round(float(deg) / 45))]
    if compact:
        return COMPACT_CARDINAL_POINTS.get(cardinal_point, "")
    return cardinal_point

def get_tail_for_flight(flight_number):
    flight_number = safe_text(flight_number).upper()
    if len(flight_number) >= 3 and flight_number[0:3] in ICAO_TO_TAIL_KEY:
        return TAILS[ICAO_TO_TAIL_KEY[flight_number[0:3]]]
    if len(flight_number) >= 3 and flight_number[2] >= "0" and flight_number[2] <= "9" and flight_number[0:2] in TAILS:
        return TAILS[flight_number[0:2]]
    if len(flight_number) == 2 and flight_number in TAILS:
        return TAILS[flight_number[0:2]]
    return TAILS["Q4"]

def to_radius_nautical_miles(distance_miles):
    distance_nm = float(distance_miles) * MILES_TO_NAUTICAL_MILES
    rounded = int(distance_nm)
    if float(rounded) < distance_nm:
        rounded = rounded + 1
    return clamp(rounded, 1, 250)

def get_aircraft_in_radius(lat, lng, distance_miles):
    radius_nm = to_radius_nautical_miles(distance_miles)
    rep = http.get(
        "%s/%s/%s/%s" % (ADSB_POINT_URL, lat, lng, radius_nm),
        ttl_seconds = DEFAULT_CACHE,
    )
    if rep.status_code != 200:
        fail("Failed to fetch flights with status code:", rep.status_code)

    return rep.json().get("ac", [])

def get_flight_distance_nm(flight):
    distance_nm = flight.get("dst")
    if is_number(distance_nm):
        return float(distance_nm)
    return 999999

def sort_aircraft_by_distance(aircraft):
    sorted_aircraft = []
    for flight in aircraft:
        insert_index = len(sorted_aircraft)
        distance_nm = get_flight_distance_nm(flight)
        for index in range(len(sorted_aircraft)):
            if distance_nm < get_flight_distance_nm(sorted_aircraft[index]):
                insert_index = index
                break
        sorted_aircraft = sorted_aircraft[:insert_index] + [flight] + sorted_aircraft[insert_index:]
    return sorted_aircraft

def get_route(callsign, lat, lng):
    callsign = safe_text(callsign).upper()
    if len(callsign) < 3:
        return None

    rep = http.get(
        "%s/%s/%s/%s" % (ADSB_ROUTE_URL, callsign, lat, lng),
        ttl_seconds = DEFAULT_CACHE,
    )
    if rep.status_code == 200:
        route = rep.json()
        if route.get("plausible") == True:
            return route

    rep = http.get(
        "%s/%s/%s.json" % (ROUTE_DATA_URL, callsign[0:2], callsign),
        ttl_seconds = DEFAULT_CACHE,
    )
    if rep.status_code != 200:
        return None
    return rep.json()

def split_route_codes(route_code_text):
    route_code_text = safe_text(route_code_text)
    if route_code_text == "" or route_code_text == "unknown" or "-" not in route_code_text:
        return None

    route_parts = route_code_text.split("-")
    if len(route_parts) < 2:
        return None

    return [safe_text(route_parts[0]), safe_text(route_parts[len(route_parts) - 1])]

def route_parts_are_useful(route_parts):
    if route_parts == None:
        return False
    origin = safe_text(route_parts[0]).upper()
    destination = safe_text(route_parts[1]).upper()
    if origin == "" or destination == "":
        return False
    if origin == "UNKNOWN" or destination == "UNKNOWN":
        return False
    if origin == destination:
        return False
    return True

def get_origin_destination(callsign, lat, lng):
    route = get_route(callsign, lat, lng)
    if route == None:
        return ["Unknown", "Unknown"]

    route_parts = split_route_codes(route.get("_airport_codes_iata"))
    if route_parts_are_useful(route_parts):
        return route_parts

    route_parts = split_route_codes(route.get("airport_codes"))
    if route_parts_are_useful(route_parts):
        return route_parts

    airports = route.get("_airports", [])
    if airports and len(airports) > 1:
        origin = safe_text(airports[0].get("iata")) or safe_text(airports[0].get("icao")) or "Unknown"
        destination = safe_text(airports[len(airports) - 1].get("iata")) or safe_text(airports[len(airports) - 1].get("icao")) or "Unknown"
        route_parts = [origin, destination]
        if route_parts_are_useful(route_parts):
            return route_parts

    return ["Unknown", "Unknown"]

def get_display_flight(lat, lng, distance_miles):
    aircraft = sort_aircraft_by_distance(get_aircraft_in_radius(lat, lng, distance_miles))
    if not aircraft:
        return None

    fallback_flight = aircraft[0]
    route_checks = 0

    for flight in aircraft:
        callsign = safe_text(flight.get("flight")).upper()
        if callsign != "" and route_checks < MAX_ROUTE_LOOKUPS:
            route_checks = route_checks + 1
            origin_destination = get_origin_destination(callsign, lat, lng)
            if route_parts_are_useful(origin_destination):
                return {
                    "flight": flight,
                    "origin": origin_destination[0],
                    "destination": origin_destination[1],
                }

    return {
        "flight": fallback_flight,
        "origin": "Unknown",
        "destination": "Unknown",
    }

def format_altitude_feet(flight):
    altitude = flight.get("alt_baro")
    if is_number(altitude):
        return humanize.comma(round_int(float(altitude)))

    altitude = flight.get("alt_geom")
    if is_number(altitude):
        return humanize.comma(round_int(float(altitude)))

    return "0"

def format_speed_mph(flight):
    speed = flight.get("gs")
    if is_number(speed):
        return humanize.comma(round_int(float(speed) * KNOTS_TO_MPH))
    return "0"

def format_distance(distance_nm, compact = False, direction = ""):
    if not is_number(distance_nm):
        if compact:
            return direction or "unknown"
        return "unknown distance"

    miles = float(distance_nm) * NAUTICAL_MILES_TO_MILES
    tenths = round_int(miles * 10)
    whole = tenths // 10
    remainder = tenths % 10
    whole_miles = round_int(miles)

    if compact:
        compact_distance = "%s mi" % whole_miles
        if whole_miles < 10 and remainder != 0:
            compact_distance = "%s.%s mi" % (whole, remainder)

        with_direction = compact_distance
        if direction != "":
            with_direction = "%s %s" % (compact_distance, direction)

        if len(with_direction) <= 9:
            return with_direction

        whole_only = "%s mi" % whole_miles
        if direction != "":
            whole_with_direction = "%s %s" % (whole_only, direction)
            if len(whole_with_direction) <= 9:
                return whole_with_direction

        return whole_only

    if remainder == 0:
        if whole == 1:
            return "1 mile"
        return "%s miles" % whole
    return "%s.%s miles" % (whole, remainder)

def get_heading_cardinal(flight):
    heading = flight.get("track")
    if is_number(heading):
        return get_cardinal_point(heading)

    heading = flight.get("true_heading")
    if is_number(heading):
        return get_cardinal_point(heading)

    return "Unknown"

def get_look_direction(flight, orig_lat, orig_lng, compact = False):
    direction = flight.get("dir")
    if is_number(direction):
        return get_cardinal_point(direction, compact)

    lat = flight.get("lat")
    lng = flight.get("lon")
    if is_number(lat) and is_number(lng):
        bearing = get_bearing(orig_lat, orig_lng, lat, lng)
        if compact:
            return COMPACT_CARDINAL_POINTS.get(bearing, "")
        return bearing

    if compact:
        return ""
    return "Unknown"

def get_flight_identifier(flight):
    callsign = safe_text(flight.get("flight")).upper()
    if callsign != "":
        return callsign

    registration = safe_text(flight.get("r")).upper()
    if registration != "":
        return registration

    return safe_text(flight.get("hex")).upper() or "Unknown"

def get_aircraft_type(flight):
    aircraft_type = safe_text(flight.get("t")).upper()
    if aircraft_type != "":
        return aircraft_type

    return safe_text(flight.get("desc")) or "Unknown"

def build_extended_text(flight, orig_lat, orig_lng):
    aircraft_type = get_aircraft_type(flight)
    return "Look %s for %s %s away, flying at %s feet, heading %s at %s mph" % (
        get_look_direction(flight, orig_lat, orig_lng),
        aircraft_type,
        format_distance(flight.get("dst")),
        format_altitude_feet(flight),
        get_heading_cardinal(flight),
        format_speed_mph(flight),
    )

def main(config):
    hide_when_nothing_to_display = config.bool("hide", True)
    extend = config.bool("extend", True)

    location = json.decode(config.get("location", DEFAULT_LOCATION))
    orig_lat = location["lat"]
    orig_lng = location["lng"]

    lat = reduce_accuracy(orig_lat)
    lng = reduce_accuracy(orig_lng)
    display_flight = get_display_flight(lat, lng, config.get("distance", DEFAULT_DISTANCE))

    if display_flight:
        flight = display_flight["flight"]
        callsign = safe_text(flight.get("flight")).upper()
        origin = display_flight["origin"]
        destination = display_flight["destination"]
        flight_number = get_flight_identifier(flight)
        tail = get_tail_for_flight(callsign or flight_number)

        if extend:
            text = [
                render.Text(origin),
                render.Text(destination),
                render.Text(flight_number),
                render.Marquee(
                    width = 32,
                    child = render.Text(build_extended_text(flight, orig_lat, orig_lng), color = "#fff"),
                ),
            ]
        else:
            text = [
                render.Text(origin),
                render.Text(destination),
                render.Text(flight_number),
                render.Text(format_distance(flight.get("dst"), compact = True, direction = get_look_direction(flight, orig_lat, orig_lng, compact = True))),
            ]
    elif hide_when_nothing_to_display == True:
        return []
    else:
        tail = TAILS["Q4"]
        text = [
            render.Text("No"),
            render.Text("Flights"),
            render.Text("Nearby"),
        ]

    return render.Root(
        child = update_display(tail, text),
        show_full_animation = True,
    )

def get_schema():
    options = [
        schema.Option(
            display = "1 mi",
            value = "1",
        ),
        schema.Option(
            display = "3 mi",
            value = "3",
        ),
        schema.Option(
            display = "6 mi",
            value = "6",
        ),
        schema.Option(
            display = "12 mi",
            value = "12",
        ),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Location",
                desc = "Your current location",
                icon = "locationDot",
            ),
            schema.Dropdown(
                id = "distance",
                name = "Distance",
                desc = "Search radius from your location.",
                icon = "rulerHorizontal",
                default = options[1].value,
                options = options,
            ),
            schema.Toggle(
                id = "hide",
                name = "Hide",
                desc = "Hide app when no flights nearby?",
                icon = "gear",
                default = False,
            ),
            schema.Toggle(
                id = "extend",
                name = "Extend",
                desc = "Show extended data for nearest flight?",
                icon = "gear",
                default = False,
            ),
        ],
    )
