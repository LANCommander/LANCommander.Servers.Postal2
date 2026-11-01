# Postal 2 Server (Docker)

This repository provides a Dockerized **Postal 2: Share the Pain** dedicated server. Share the Pain is Postal 2's multiplayer (Running With Scissors, 2003, Unreal Engine 2). The image runs the retail Windows game's `UCC.exe server` under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs the retail game's `UCC.exe server` (headless; no X display, graphics or sound)
- A separate server ini (`System/Server.ini`) is created from the game's `Default.ini`, and the common settings are environment variables
- Map rotations can be set per game type, and maps that aren't installed are dropped from the rotations
- The master server uplink is removed by default
- UCC's console log goes to `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  postal2:
    image: lancommander/postal2:latest
    container_name: postal2

    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"
      - "8777:8777/udp"

    volumes:
      - ./config:/config

    environment:
      P2_SERVER_NAME: "My Postal 2 Server"
      P2_MAP: "MPDGT-Asylum"
      P2_GAME_TYPE: "MultiGame.xDeathMatch"
      P2_MAX_PLAYERS: "16"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser finds servers by broadcast. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`). With port mapping, clients join by IP.

---

## Game Files

Postal 2 is retail software with no public download. You must provide a **Share the Pain 1409** install (the folder with `System/Postal2MP.exe` and `System/UCC.exe`; in a full Postal 2 install that is `ShareThePain/`). Clients must run the same version.

- copy that folder's contents (`System/`, `Maps/`, `Textures/` ...) to `config/Server/`, **or**
- set `P2_ARCHIVE_URL` to a zip of it, e.g. a LANCommander archive. It is downloaded and extracted on first start, if `Server/System/UCC.exe` doesn't exist yet. A zip of a full Postal 2 install works too; only its `ShareThePain/` folder is kept.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Share the Pain install (System/, Maps/, Textures/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (System/Server.ini and server.log land here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The ini settings are written into `P2_INI` on every start. Settings left empty are not touched, so you can set them in the ini instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `P2_MAP` | Start map, see below | `MPDGT-Asylum` |
| `P2_GAME_TYPE` | Game class, see below | `MultiGame.xDeathMatch` |
| `P2_ADMIN_PASSWORD` | Admin password, passed as the `?AdminPassword=` URL option (the engine has no ini setting for it) | |
| `P2_URL_OPTIONS` | Extra map URL options, e.g. `MaxPlayers=8?GamePassword=x` | |
| `P2_INI` | Server ini in `System/`, created from `Default.ini` if missing | `Server.ini` |
| `P2_PORT` | Game port, `[URL] Port`. The query port is this + 1 | `7777` |
| `P2_SERVER_NAME` | `[Engine.GameReplicationInfo] ServerName` | `Postal 2 Server` |
| `P2_SHORT_NAME` | `[Engine.GameReplicationInfo] ShortName` | `Postal 2 Server` |
| `P2_ADMIN_NAME` | `[Engine.GameReplicationInfo] AdminName` | |
| `P2_ADMIN_EMAIL` | `[Engine.GameReplicationInfo] AdminEmail` | |
| `P2_MOTD` | `[Engine.GameReplicationInfo] MOTDLine1` | |
| `P2_MAX_PLAYERS` | `[Engine.GameInfo] MaxPlayers` | `16` |
| `P2_GAME_PASSWORD` | `[Engine.AccessControl] GamePassword` | |
| `P2_GOAL_SCORE` | `GoalScore` (frags, captures ...) in the `P2_GAME_TYPE` section | |
| `P2_TIME_LIMIT` | `TimeLimit` in minutes in the `P2_GAME_TYPE` section | |
| `P2_MIN_PLAYERS` | `[MultiBase.MPGameInfo] MinPlayers`: bots fill the server up to this many players | |
| `P2_BOT_DIFFICULTY` | `[MultiBase.MPGameInfo] BotDifficulty` | |
| `P2_MAPS` | Map rotation for `P2_GAME_TYPE`, comma separated (`.fuk` is optional) | |
| `P2_MASTER_SERVER_UPLINK` | `true` keeps the `UdpServerUplink` server actor (master server listing) | `false` |
| `P2_ARCHIVE_URL` | Zip of the game folder, used if `Server/System/UCC.exe` is missing | |
| `WINE_XVFB` | UCC needs no display | `false` |
| `START_EXE` | Launcher | `/usr/local/bin/p2-server` |
| `START_ARGS` | Appended to the UCC command line | |

Game types and their map lists:

| `P2_GAME_TYPE` | Mode | Map list section | Maps |
|----------------|------|------------------|------|
| `MultiGame.xDeathMatch` | Deathmatch | `[MultiGame.DMMapList]` | `MPDGT-*` |
| `MultiGame.xTeamGame` | Team Deathmatch | `[MultiGame.TDMMapList]` | `MPDGT-*` |
| `MultiGame.xCTFGame` | Snatch (capture the babe) | `[MultiGame.CTFMapList]` | `MPS-*` |
| `MultiGame.xGrabBag` | Grab Bag | `[MultiGame.GBMapList]` | `MPDGT-*` |

Retail 1409 maps: `MPDGT-Asylum`, `MPDGT-Boneyard`, `MPDGT-Cemetery`, `MPDGT-IceHole`, `MPDGT-MeatWorld`, `MPDGT-Monsoon`, `MPDGT-Napalm`, `MPDGT-Piquant`, `MPDGT-Shantytown`, `MPDGT-Trainyard`, `MPS-Intifada`, `MPS-Ponderous`, `MPS-RedLight`, `MPS-SplinterFoundry`.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/postal2:local .
```

---

## License

Postal 2 and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
