#!/bin/bash
# Modded Beat Saber for the Steam Frame: one-command installer.
#
#   curl -fsSL https://github.com/jimas21/frame-modded-beatsaber/releases/latest/download/install.sh | bash
#
# Puts Beat Saber 1.40.8 (the version every custom-map mod supports) next to your normal Beat Saber,
# installs a pinned, checksum-verified set of 33 mods from BeatMods, and adds "Beat Saber (Modded)"
# to your Steam library as a VR game. Your normal Beat Saber is not touched.
#
# Options:
#   --uninstall   remove the shortcut and the modded copy (asks first: your downloaded songs are in it)
#   --yes         don't ask (with --uninstall)
#   --help
set -euo pipefail

APPID=620980
DEPOT=620981
MANIFEST=8437413909225671968     # Beat Saber 1.40.8 on Steam
BUILD_TAG=1.40.8_7379
PROTON_TOOL=proton_11-arm64      # Steam's "Proton 11.0 (ARM64)"
NAME="${BS_SHORTCUT_NAME:-Beat Saber (Modded)}"
STEAM="$HOME/.local/share/Steam"
INSTANCE="${BS_INSTANCE_DIR:-$HOME/.local/share/BSManager/BSInstances/1.40.8}"
STATE="$HOME/.local/share/frame-modded-beatsaber"
CACHE="$STATE/cache"
FLAG="$HOME/.steam/steam/.cef-enable-remote-debugging"
MARKER="$STATE/created-cef-flag"
SENTINEL=".frame-modded-beatsaber"   # written into the game folder this installer downloads
CEF=127.0.0.1:8080

# md5 (BeatMods zipHash)  version  name. Resolved from BeatMods for game version 1.40.8, dependencies included.
MODS="
22ddb9499bf8b308ea30d2b555172baf 4.3.6 BSIPA
146b940124681179768738b8ab336103 3.15.3 SongCore
a740c6e68a9b5d1dfda3cc8e81f7cf06 6.0.7 BeatSaverDownloader
d9ea8dd0cbaac66cbb02fa59a548e42b 1.2.11 BeatSaverUpdater
bc002ed1a43e2c6d3a10d0750e5d94b4 2.4.6 BeatSaverVoting
777baaf710606b7a194ba26c794cc755 1.7.3 PlaylistManager
edb61862ace9b2b0f595a34c0a96f60f 0.8.1 BetterSongSearch
827d315b4e65bcaba816aa2dfd76c10f 0.4.2 BetterSongList
740e84fbcacf14d6cb738562bcc641ec 2.9.20+1.40.3 Chroma
100df346d07fd0e820460e0eaf32bf9f 1.7.18+1.40.3 NoodleExtensions
5648166a9a37db91d9de834172c02b07 1.7.6 MappingExtensions
1ee5bfec4dbb649141f8ff5d63e2ac61 1.0.5+1.40.3 Vivify
5977d5b8a4db74b438e552da18532b7f 1.7.14+1.40.3 Heck
fed31638bbb678580ef760ec83cfd486 2.6.8+1.40.0 CustomJSONData
26244ec8e341e9c96f59a67c39875cbe 0.9.33-1.40.2 BeatLeader
06d8fc9416614aae337893c280bc114c 3.3.17 ScoreSaber
9447ccfdf0badb1c06bbed1e8911e19d 1.0.3 WhyIsThereNoLeaderboard
9420b5ad75c00df8a17ba7170d241344 1.1.10 AssetBundleLoadingTools
b8245da532d16147d15daab5fc735c46 1.14.2 BS_Utils
ce406862c55fdc1b572f99f8e4dbd1eb 1.12.5 BeatSaberMarkupLanguage
a3418b75ed7294a3856f3eca12bbd672 1.7.2 BeatSaberPlaylistsLib
be37e13e93d9ac7da4efbdc3f514fa8f 3.4.5 BeatSaverSharp
471d40a9a5c951f4e7f5520096f00bdb 1.0.7 CameraUtils
b642fec88b0f84a0643ebd401d08da35 2.0.0 ImageSharp
5df74ad1c6b120fecdc615dd55f15b88 2.5.9 Ini_Parser
e9303bea2923995c94574c76901fd8b5 1.7.0 LeaderboardCore
5f5655b91193602c0311b8b6d1b4c71c 1.0.1 LookupID
8713168c598577ee7c73fa3cf0e26f5c 0.1.0 ScoreSaberSharp
5b90d82d3a9c095747c0ec8cde199d4c 3.2.1 SiraUtil
e1167b64cd3eff7e3651ec2dbbe50d81 1.4.0 SongDetailsCache
a4e9e26f61967e56168e08eecb01ab88 4.6.57 System.IO.Compression
e19f6fd395d54de7bfcbbbe3084dea28 4.7.3056 System.IO.Compression.FileSystem
1f55ae4b80b747b5f03fa18337ead864 3.0.102 protobuf-net
"

say()  { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

ask() { # ask "question" -> 0 for yes. Reads the terminal even under curl | bash.
    [ "${ASSUME_YES:-0}" = 1 ] && return 0
    local a=""
    if [ -r /dev/tty ]; then read -r -p "$1 [y/N] " a < /dev/tty || true; fi
    [[ "$a" =~ ^[Yy] ]]
}

# --- Steam UI bridge -----------------------------------------------------------------------------
# Steam's own UI exposes its client API on a local DevTools port when the
# ~/.steam/steam/.cef-enable-remote-debugging file exists. That is how this installer asks Steam,
# signed in as you, to download 1.40.8 (no password needed) and to add the library shortcut.
write_cef_helper() {
    cat > "$TMP/cef.py" <<'PY'
import base64, json, os, socket, struct, sys, urllib.request
expr = sys.argv[1]
targets = json.load(urllib.request.urlopen("http://127.0.0.1:8080/json", timeout=5))
t = next((t for t in targets if t.get("title") == "SharedJSContext"), None)
if not t:
    sys.exit("Steam's SharedJSContext page was not found")
path = t["webSocketDebuggerUrl"].split("127.0.0.1:8080", 1)[1]
s = socket.create_connection(("127.0.0.1", 8080), timeout=30)
key = base64.b64encode(os.urandom(16)).decode()
s.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf:
    chunk = s.recv(4096)
    if not chunk: sys.exit("websocket handshake: connection closed")
    buf += chunk
if b" 101 " not in buf.split(b"\r\n")[0]:
    sys.exit("websocket handshake failed")
rest = buf.split(b"\r\n\r\n", 1)[1]
def send(obj):
    data = json.dumps(obj).encode(); mask = os.urandom(4); n = len(data)
    if n < 126: hdr = bytes([0x81, 0x80 | n])
    elif n < 65536: hdr = bytes([0x81, 0x80 | 126]) + struct.pack(">H", n)
    else: hdr = bytes([0x81, 0x80 | 127]) + struct.pack(">Q", n)
    s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
def exact(n):
    global rest
    while len(rest) < n:
        chunk = s.recv(65536)
        if not chunk: raise EOFError
        rest += chunk
    out, rest = rest[:n], rest[n:]
    return out
def recv():
    msg = b""
    while True:
        b1, b2 = exact(2); n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", exact(2))[0]
        elif n == 127: n = struct.unpack(">Q", exact(8))[0]
        msg += exact(n)
        if b1 & 0x80: return msg
send({"id": 1, "method": "Runtime.evaluate",
      "params": {"expression": expr, "awaitPromise": True, "returnByValue": True}})
while True:
    r = json.loads(recv())
    if r.get("id") == 1:
        res = r.get("result", {})
        if "exceptionDetails" in res:
            sys.exit("Steam UI error: " + json.dumps(res["exceptionDetails"].get("exception", {}).get("description", res["exceptionDetails"]))[:400])
        v = res.get("result", {}).get("value")
        print(v if isinstance(v, str) else json.dumps(v))
        break
PY
}
cef() { python3 "$TMP/cef.py" "$1"; }
cef_up() { local j; j="$(curl -fs --max-time 3 "http://$CEF/json" 2>/dev/null || true)"; grep -q '"SharedJSContext"' <<< "$j"; }

jstr() { printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; }
# Shortcut lookup: Steam shortcuts are app_type 1073741824 in the library store. Prints the app id or nothing.
find_shortcut() {
    local id
    id="$(cef "(() => { const a = appStore.allApps.filter(x => x.app_type === 1073741824 && x.display_name === $(jstr "$NAME")); return a.length ? String(a[0].appid) : ''; })()")"
    [[ "$id" =~ ^[0-9]+$ ]] && echo "$id" || true
}

# True when this copy of the game is running. Proton shows it both as the Linux path and as the
# Wine path (Z:\home\...\Beat Saber.exe), so match either form of exactly this instance.
game_running() {
    local procs win
    procs="$(ps -eo args 2>/dev/null || true)"
    win="Z:${INSTANCE//\//\\}\\Beat Saber.exe"
    grep -F -q -- "$INSTANCE/Beat Saber.exe" <<< "$procs" || grep -F -q -- "$win" <<< "$procs"
}

# Remove the DevTools switch again if this installer created it and nothing else installed uses it.
restore_flag() {
    [ -f "$MARKER" ] || return 0
    local users=""
    for u in earshot-steamui.service magicpods-steamui.service plugin_loader.service; do
        systemctl --user cat "$u" >/dev/null 2>&1 && users="$users $u"
    done
    [ -d "$HOME/homebrew" ] && users="$users decky"
    if [ -n "$users" ]; then
        say "Leaving Steam's DevTools switch on: also used by$users"
    else
        rm -f "$FLAG"
        say "Turned Steam's DevTools switch back off (takes effect the next time Steam restarts)"
    fi
    rm -f "$MARKER"
}

# --- uninstall ----------------------------------------------------------------------------------
uninstall() {
    if [ -d "$INSTANCE" ] && game_running; then die "the modded Beat Saber is running; quit it first"; fi
    if cef_up; then
        local id; id="$(find_shortcut)"
        if [ -n "$id" ]; then
            cef "(() => { SteamClient.Apps.RemoveShortcut($id); return 'ok'; })()" >/dev/null
            say "Removed \"$NAME\" from your library"
        else
            say "No \"$NAME\" shortcut in your library"
        fi
    else
        warn "Steam's DevTools port is closed, so remove \"$NAME\" from your library by hand"
    fi
    if [ -d "$INSTANCE" ] && [ ! -f "$INSTANCE/$SENTINEL" ]; then
        say "Kept $INSTANCE: this installer did not create it"
    elif [ -d "$INSTANCE" ]; then
        if ask "Delete $INSTANCE (the modded game AND every custom song you downloaded into it)?"; then
            rm -rf "$INSTANCE"
            say "Deleted $INSTANCE"
        else
            say "Kept $INSTANCE"
        fi
    fi
    rm -rf "$CACHE"
    restore_flag
    say "Uninstalled. Your normal Beat Saber was never changed."
}

# --- install steps --------------------------------------------------------------------------------
check_system() {
    [ "$(uname -m)" = aarch64 ] || die "this installer is for the Steam Frame (ARM64)"
    [ -d "$STEAM" ] || die "Steam was not found at $STEAM"
    for t in curl python3 unzip md5sum; do command -v "$t" >/dev/null || die "$t is required"; done
    [ -d "$STEAM/steamapps/common/Proton 11.0 (ARM64)" ] ||
        die "Proton 11.0 (ARM64) is not installed. Start any Windows game once (your normal Beat Saber works), or install it from the Library under Tools, then run this again."
}

ensure_cef() {
    if cef_up; then return 0; fi
    if [ ! -e "$FLAG" ]; then
        mkdir -p "$STATE"
        : > "$FLAG"
        : > "$MARKER"
        echo
        say "One-time step: Steam needs a restart to let this installer talk to it."
        say "Restart your Steam Frame (hold the power button > Restart), then run the same command again."
        say "It will pick up from here and turn this switch back off when it is done."
        exit 0
    fi
    die "Steam's DevTools port is not open yet. Restart your Steam Frame, then run this again."
}

download_game() {
    if [ -f "$INSTANCE/Beat Saber.exe" ] && grep -a -q "$BUILD_TAG" "$INSTANCE/Beat Saber_Data/globalgamemanagers" 2>/dev/null; then
        say "Beat Saber 1.40.8 is already at $INSTANCE"
        return 0
    fi
    [ -e "$INSTANCE" ] && die "$INSTANCE exists but is not Beat Saber 1.40.8; move it away first"

    local log="$STEAM/logs/console_log.txt" start dst="" scratch
    # Steam's download_depot scratch area keeps a state file per depot. If one is left from an
    # earlier download, Steam reports "complete" at once and leaves an empty folder, so clear
    # it first. This is only the download_depot work area, never the real game in steamapps/common.
    while IFS= read -r scratch; do
        [ -n "$scratch" ] && rm -rf -- "$scratch"
    done < <(find "$STEAM" -maxdepth 5 -type d -path "*/steamapps/content/app_$APPID" 2>/dev/null)
    start=$( [ -f "$log" ] && stat -c %s "$log" || echo 0 )
    say "Asking Steam to download Beat Saber 1.40.8 (about 1.3 GB) with your account"
    cef "(() => { SteamClient.Console.ExecCommand('download_depot $APPID $DEPOT $MANIFEST'); return 'ok'; })()" >/dev/null

    local i line
    for i in $(seq 1 720); do   # up to 60 minutes
        sleep 5
        [ "$(stat -c %s "$log" 2>/dev/null || echo 0)" -lt "$start" ] && start=0   # log was rotated
        line="$(tail -c +"$((start + 1))" "$log" 2>/dev/null | grep -a -E "Depot download (complete|failed)|download_depot.*(fail|error|not own)" | tail -1 || true)"
        case "$line" in
            *"Depot download complete"*) break ;;
            *) [ -n "$line" ] && die "Steam could not download it: $line (do you own Beat Saber on Steam?)" ;;
        esac
        if [ $((i % 6)) = 0 ]; then
            dst="$(find "$STEAM" -maxdepth 6 -type d -path "*content/app_$APPID/depot_$DEPOT" 2>/dev/null | head -1 || true)"
            [ -n "$dst" ] && echo "    $(du -sh "$dst" 2>/dev/null | cut -f1) of ~1.3 GB"
        fi
    done
    [[ "$line" == *"Depot download complete"* ]] || die "the download did not finish within an hour"
    dst="$(find "$STEAM" -maxdepth 6 -type d -path "*content/app_$APPID/depot_$DEPOT" 2>/dev/null | head -1 || true)"
    [ -n "$dst" ] && [ -f "$dst/Beat Saber.exe" ] || die "the download finished but its folder was not found"
    grep -a -q "$BUILD_TAG" "$dst/Beat Saber_Data/globalgamemanagers" || die "the downloaded game is not 1.40.8"
    mkdir -p "$(dirname "$INSTANCE")"
    mv "$dst" "$INSTANCE"
    echo "Downloaded by frame-modded-beatsaber; --uninstall deletes this folder only when this file exists." > "$INSTANCE/$SENTINEL"
    rmdir "$(dirname "$dst")" 2>/dev/null || true
    say "Beat Saber 1.40.8 is at $INSTANCE"
}

install_mods() {
    mkdir -p "$CACHE"
    local md5 ver name z n=0
    say "Downloading and verifying 33 mods from BeatMods"
    while read -r md5 ver name; do
        [ -n "$md5" ] || continue
        z="$CACHE/$name-$ver.zip"
        if [ ! -f "$z" ] || [ "$(md5sum "$z" | cut -d' ' -f1)" != "$md5" ]; then
            curl -fsSL --retry 3 -A "frame-modded-beatsaber" -o "$z.part" "https://beatmods.com/cdn/mod/$md5.zip" ||
                die "could not download $name"
            [ "$(md5sum "$z.part" | cut -d' ' -f1)" = "$md5" ] || { rm -f "$z.part"; die "checksum mismatch for $name"; }
            mv "$z.part" "$z"
        fi
        # Mod files are replaced; files under UserData (your mod settings) are only added, never overwritten.
        unzip -Z1 "$z" > "$TMP/list" || die "$name is not a valid zip"
        if grep -q '^UserData/' "$TMP/list"; then
            unzip -o -q "$z" -x 'UserData/*' -d "$INSTANCE" || [ $? -le 1 ] || die "could not unpack $name"
            unzip -n -q "$z" 'UserData/*' -d "$INSTANCE" || [ $? -le 1 ] || die "could not unpack $name"
        else
            unzip -o -q "$z" -d "$INSTANCE" || [ $? -le 1 ] || die "could not unpack $name"
        fi
        n=$((n + 1))
    done <<< "$MODS"
    [ "$n" = 33 ] || die "expected 33 mods, installed $n"

    # BSIPA's own installer (IPA.exe) does exactly these copies. The game is started with
    # WINEDLLOVERRIDES=winhttp=n,b so Proton loads BSIPA's winhttp.dll.
    cp -r "$INSTANCE/IPA/Data/." "$INSTANCE/Beat Saber_Data/"
    mkdir -p "$INSTANCE/Libs" "$INSTANCE/Plugins" "$INSTANCE/UserData"
    cp -r "$INSTANCE/IPA/Libs/." "$INSTANCE/Libs/"
    find "$INSTANCE/IPA" -maxdepth 1 -type f -exec cp {} "$INSTANCE/" \;
    echo "$APPID" > "$INSTANCE/steam_appid.txt"
    say "Mods installed ($(ls "$INSTANCE/Plugins" | grep -c '\.dll$') plugin files)"
}

add_shortcut() {
    local js_name js_exe js_dir id
    js_name="$(jstr "$NAME")"
    js_exe="$(jstr "\"$INSTANCE/Beat Saber.exe\"")"
    js_dir="$(jstr "\"$INSTANCE\"")"
    id="$(find_shortcut)"
    if [ -z "$id" ]; then
        id="$(cef "(async () => String(await SteamClient.Apps.AddShortcut($js_name, $js_exe, '', '')))()")"
        [[ "$id" =~ ^[1-9][0-9]*$ ]] || die "Steam did not create the shortcut ($id)"
        say "Added \"$NAME\" to your library"
    else
        say "Updating the existing \"$NAME\" shortcut"
    fi
    cef "(async () => {
        const id = $id;
        SteamClient.Apps.SetShortcutName(id, $js_name);
        SteamClient.Apps.SetShortcutExe(id, $js_exe);
        SteamClient.Apps.SetShortcutStartDir(id, $js_dir);
        SteamClient.Apps.SetShortcutLaunchOptions(id, 'WINEDLLOVERRIDES=\"winhttp=n,b\" %command%');
        SteamClient.Apps.SpecifyCompatTool(id, '$PROTON_TOOL');
        SteamClient.Apps.SetShortcutIsVR(id, true);
        return 'ok';
    })()" >/dev/null

    # Read it back from Steam to be sure every setting stuck.
    local got
    got="$(cef "(async () => { const id = $id; let d = appDetailsStore.GetAppDetails(id);
        if (!d || !d.strCompatToolName) {
            await new Promise(r => { const h = SteamClient.Apps.RegisterForAppDetails(id, x => { d = x; try { h.unregister(); } catch (e) {} r(); });
                                    setTimeout(r, 5000); }); }
        const o = appStore.GetAppOverviewByAppID(id) || {};
        return JSON.stringify({exe: d && d.strShortcutExe, opts: d && d.strLaunchOptions, tool: d && d.strCompatToolName, vr: !!o.vr_supported}); })()")"
    echo "$got" | grep -q "winhttp=n,b" && echo "$got" | grep -q "$PROTON_TOOL" && echo "$got" | grep -q '"vr": *true\|"vr":true' ||
        warn "could not confirm every shortcut setting: $got"
}

main() {
    case "${1:-}" in
        -h|--help) sed -n '2,15p' "$0" 2>/dev/null || echo "see https://github.com/jimas21/frame-modded-beatsaber"; exit 0 ;;
    esac
    ASSUME_YES=0; local mode=install
    for a in "$@"; do
        case "$a" in
            --uninstall) mode=uninstall ;;
            --yes|-y) ASSUME_YES=1 ;;
            *) die "unknown option $a" ;;
        esac
    done
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    write_cef_helper
    mkdir -p "$STATE"

    if [ "$mode" = uninstall ]; then uninstall; exit 0; fi

    check_system
    game_running && die "the modded Beat Saber is running; quit it first"
    ensure_cef
    download_game
    install_mods
    add_shortcut
    restore_flag
    echo
    say "Done. In your Steam library, launch \"$NAME\"."
    say "The first start takes a minute or two while Proton and the mod loader set up."
}

main "$@"
