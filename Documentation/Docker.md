---
sidebar_label: Docker
---

# Postal 2 Docker Container

This Docker container runs a Postal 2: Share the Pain dedicated server. It is built on the WINE image and runs the retail game's Unreal Engine 2 server, `UCC.exe server`. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  postal2:
    image: lancommander/postal2:latest
    container_name: postal2

    ports:
      - 7777:7777/udp
      - 7778:7778/udp
      - 8777:8777/udp

    volumes:
      - "/data/Servers/Postal 2/Deathmatch:/config"

    environment:
      P2_SERVER_NAME: "My Postal 2 Server"
      P2_MAP: "MPDGT-Asylum"
      P2_GAME_TYPE: "MultiGame.xDeathMatch"
      P2_ADMIN_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy a Share the Pain **1409** install (the folder with `System/Postal2MP.exe`, `System/UCC.exe` and `Maps/`; `ShareThePain/` in a full Postal 2 install) into `Server/` before the first start. You can instead set `P2_ARCHIVE_URL` to a zip of that folder or of a full Postal 2 install.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallPostal2.ps1` checks for `Server/System/UCC.exe`. If it's missing and `P2_ARCHIVE_URL` is set, the hook downloads the archive, extracts the folder that holds `System/Postal2MP.exe`, and remounts the overlay.
3. `PostInitialization/30-ConfigurePostal2.ps1` copies `System/Default.ini` to `System/Server.ini` (`P2_INI`) if it doesn't exist yet. It does this through `Merged/`, so the file lands in `Overlay/System/`. It then writes the non-empty `P2_*` settings into it, sets the map rotation, drops maps that aren't in `Maps/` from every rotation, and removes the master server uplink.
4. `START_EXE` (`/usr/local/bin/p2-server`) runs `UCC.exe server <P2_MAP>?Game=<P2_GAME_TYPE>[?AdminPassword=...] ini=Server.ini log=server.log` from `System/` under Wine.

A successful start ends with:

```
Game class is 'xDeathMatch'
TcpNetDriver on port 7777
...
UdpServerQuery(crt): Port 7778 successfully bound.
...
Game engine initialized
```

## Configuration Options

### Ports

- **7777/udp**: Game (`P2_PORT`)
- **7778/udp**: Server query, GameSpy protocol (game port + 1). `\status\` returns the name, map, game type, version (`gamever 1409`) and rules.
- **8777/udp**: LAN beacon. The in-game LAN browser broadcasts `REPORTQUERY` here, and the server replies `postal2 7778`.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Server ini

`Overlay/System/Server.ini` is yours to edit. Only the keys that have a non-empty `P2_*` variable are rewritten on start. Delete the file to regenerate it from `Default.ini`.

- Mode rules are per game type, e.g. `[MultiGame.xDeathMatch] GoalScore` / `TimeLimit` or `[MultiGame.xCTFGame] FriendlyFireScale`. `P2_GOAL_SCORE` and `P2_TIME_LIMIT` go into the section of the current `P2_GAME_TYPE`.
- Bots: `[MultiBase.MPGameInfo] MinPlayers` (bots fill up to this many players), `bAutoFillBots`, `BotDifficulty`.
- Map rotations: `Maps[0]`..`Maps[31]` in `[MultiGame.DMMapList]`, `TDMMapList`, `CTFMapList` and `GBMapList`. `P2_MAPS` replaces the list of the current game type.
- Web admin: `[UWeb.WebServer] bEnabled=True` (and `ListenPort`) turns on the UTServerAdmin web interface. It is off by default; expose its TCP port if you enable it.

UCC saves its config to the server ini on exit, so values can also change there after an admin command.

### Hooks

| Hook | When |
|------|------|
| `PreInstallPostal2` / `PostInstallPostal2` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to 8777, so the container needs its own LAN address (macvlan/ipvlan) or host networking. Joining by IP works through port mapping.
- **Clients can't join / version mismatch**: the server reports `gamever 1409` and `minnetver 1407`. Clients need Share the Pain 1409 with the same packages.
- **Admin password in the logs**: the engine only reads the admin password from the map URL, so it appears in the `Browse:`/`LoadMap:`/`InitGame:` lines of `docker logs` and `server.log`.
- **Settings ignored**: they go into `P2_INI`, not `Postal2MP.ini` or `Default.ini`. Check `Overlay/System/Server.ini`.
- **`P2_MASTER_SERVER_UPLINK=true` has no effect on an existing ini**: the uplink server actor was removed from it on an earlier start. Add `ServerActors=IpDrv.UdpServerUplink MasterServerAddress=... MasterServerPort=...` back under `[Engine.GameEngine]`, or delete the ini.
- **`System/UCC.exe not found`**: `Server/` must contain the Share the Pain folder itself (`Server/System/UCC.exe`), not a folder that contains it.
