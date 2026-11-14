# Modded Beat Saber for the Steam Frame

Custom songs and every popular custom-map mod, standalone on the Valve Steam Frame, in one click.

It puts **Beat Saber 1.40.8** next to your normal Beat Saber, installs a fixed set of 33 mods, and
adds **Beat Saber (Modded)** to your Steam library as a VR game. Your normal Beat Saber is not
changed and keeps updating as usual.

## Install

There is no password to enter. You need to own Beat Saber on Steam.

1. In a web browser on the headset, open this page and press the button:

   <a href="https://github.com/jimas21/frame-modded-beatsaber/releases/latest/download/Install-Modded-BeatSaber.desktop"><img src="img/install-button.svg" alt="Install Modded Beat Saber" width="300" /></a>

2. Open the file it downloads, `Install-Modded-BeatSaber.desktop`. If you are asked whether to
   trust it, say yes. A window opens and does the rest.
3. **First time only:** if the window says Steam needs a restart, restart the headset, then open
   the same file again. It continues where it stopped.
4. When the window says **Done**, launch **Beat Saber (Modded)** from your library. The first
   start takes a minute or two.

In the game, **More Songs** (left of the song list) browses and downloads maps from BeatSaver.

## What you get

| | Mods |
|---|---|
| Custom songs | SongCore, BeatSaverDownloader, BeatSaverUpdater, BeatSaverVoting, PlaylistManager, BetterSongSearch, BetterSongList |
| Map requirements | Chroma, Noodle Extensions, Mapping Extensions, Vivify, Heck, CustomJSONData |
| Leaderboards | BeatLeader, ScoreSaber |
| Loader and libraries | BSIPA 4.3.6 plus the 17 libraries the mods above need |

**Why 1.40.8 and not the latest Beat Saber?** It is the newest version every map mod (Chroma,
Noodle Extensions, Mapping Extensions, Vivify) is built for, so it is the one the custom-map
community plays on. Newer versions have few or none of them yet.

It runs through Proton 11.0 (ARM64) the same way your normal Beat Saber does on the Frame.

## What it does, step by step

1. Checks that this is a Steam Frame and that Proton 11.0 (ARM64) is installed.
2. Talks to your running Steam through Steam's own local DevTools port. If that port is closed it
   creates `~/.steam/steam/.cef-enable-remote-debugging` (Steam opens the port only when this file
   exists) and asks you to restart once. When the install is finished it deletes that file again,
   unless something else you have installed uses it too (Tragus, Earshot, Decky).
3. Asks Steam to download Beat Saber 1.40.8 with your account, using Steam's own
   `download_depot 620980 620981 8437413909225671968` command, and moves it to
   `~/.local/share/BSManager/BSInstances/1.40.8`. That is where
   [BSManager](https://github.com/DaVarga/bs-manager) keeps its versions, so it shows up there too
   if you use BSManager.
4. Downloads the 33 mods from [BeatMods](https://beatmods.com), checks each one against the MD5
   pinned in `install.sh`, and unpacks them. Your mod settings in `UserData` are never overwritten.
5. Installs the BSIPA mod loader the same way its own installer does.
6. Adds the **Beat Saber (Modded)** shortcut: Proton 11.0 (ARM64), the launch option
   `WINEDLLOVERRIDES="winhttp=n,b" %command%` (which turns the mod loader on), and marked as a VR
   game so it opens in VR.

Running it again is safe: it skips the download, re-checks the mods and updates the shortcut.

## Uninstall

<a href="https://github.com/jimas21/frame-modded-beatsaber/releases/latest/download/Uninstall-Modded-BeatSaber.desktop"><img src="img/uninstall-button.svg" alt="Uninstall Modded Beat Saber" width="300" /></a>

It removes the shortcut, then asks before deleting the modded copy, because the custom songs you
downloaded live inside it.

## From a terminal

```sh
curl -fsSL https://github.com/jimas21/frame-modded-beatsaber/releases/latest/download/install.sh | bash
curl -fsSL https://github.com/jimas21/frame-modded-beatsaber/releases/latest/download/install.sh | bash -s -- --uninstall
```

## Credits

The mods are downloaded from BeatMods at install time and belong to their authors (BSIPA by the
BSMG team, Chroma, Noodle Extensions, Heck and Vivify by Aeroluna, and many more). This repository
only contains the installer. Unofficial; not affiliated with Beat Games, Meta or Valve.
