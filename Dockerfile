# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Postal 2: Share the Pain (1409) install in
#     /config/Server, or set P2_ARCHIVE_URL to a zip of one
#   - P2_INI is created from System/Default.ini on first start; the P2_* settings below are
#     written into it on every start (empty settings are left alone)
#   - UCC is a console program and needs no X display, so Xvfb is off
# ----------------------------
ENV P2_ARCHIVE_URL="" \
    P2_MAP="MPDGT-Asylum" \
    P2_GAME_TYPE="MultiGame.xDeathMatch" \
    P2_PORT="7777" \
    P2_INI="Server.ini" \
    P2_SERVER_NAME="Postal 2 Server" \
    P2_SHORT_NAME="Postal 2 Server" \
    P2_ADMIN_NAME="" \
    P2_ADMIN_EMAIL="" \
    P2_MOTD="" \
    P2_MAX_PLAYERS="16" \
    P2_GAME_PASSWORD="" \
    P2_ADMIN_PASSWORD="" \
    P2_GOAL_SCORE="" \
    P2_TIME_LIMIT="" \
    P2_MIN_PLAYERS="" \
    P2_BOT_DIFFICULTY="" \
    P2_MAPS="" \
    P2_MASTER_SERVER_UPLINK="false" \
    P2_URL_OPTIONS="" \
    WINE_XVFB="false" \
    START_EXE="/usr/local/bin/p2-server" \
    START_ARGS=""

COPY Scripts/p2-server /usr/local/bin/p2-server
RUN chmod +x /usr/local/bin/p2-server

COPY Hooks/ "${BASE_HOOKS}/"

# 7777/udp: game. 7778/udp: server query (game port + 1). 8777/udp: LAN browser beacon (UdpBeacon
# answers REPORTQUERY broadcasts there).
EXPOSE 7777/udp 7778/udp 8777/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
