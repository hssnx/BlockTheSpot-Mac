#!/usr/bin/env bash
#
# BlockTheSpot-Mac installer / patcher
# Snapshot-layout support, version-range guard (base-10), and GNU-sed fallback
# Last updated: 2025-05-21

BLOCKTHESPOT_VERSION="1.2.32.985.g3be2709c"

###############################################################################
# 1 ── Dependency check
###############################################################################
command -v perl  >/dev/null || { echo -e "\nperl not found, exiting…\n"  >&2; exit 1; }
command -v unzip >/dev/null || { echo -e "\nunzip not found, exiting…\n" >&2; exit 1; }
command -v zip   >/dev/null || { echo -e "\nzip   not found, exiting…\n" >&2; exit 1; }

# Require GNU-sed (gsed) even when called via sudo
SED=$(command -v gsed 2>/dev/null)
if [[ -z $SED ]]; then
  echo "GNU sed (gsed) not found – brew install gnu-sed and retry"; exit 1
fi
alias sed="$SED"


###############################################################################
# 2 ── CLI flags
###############################################################################
APP_PATH="/Applications/Spotify.app"
FORCE_FLAG=false
HIDE_PODCASTS_FLAG=false
PATH_FLAG=false
UPDATE_FLAG=false
SKIP_CODE_SIGNATURE=false
DEVELOPER_MODE=false
UNINSTALL_FLAG=false

while getopts 'UfhSPud:' flag; do
  case "${flag}" in
    U) UNINSTALL_FLAG=true  ;;
    f) FORCE_FLAG=true      ;;
    h) HIDE_PODCASTS_FLAG=true ;;
    S) SKIP_CODE_SIGNATURE=true ;;
    d) DEVELOPER_MODE=true  ;;
    P) APP_PATH="${OPTARG}"; PATH_FLAG=true ;;
    u) UPDATE_FLAG=true     ;;
    *) echo "Error: flag not supported"; exit 1 ;;
  esac
done

###############################################################################
# 3 ── Path resolution
###############################################################################
if ! $PATH_FLAG; then
  if [[ -d "${HOME}${APP_PATH}" ]]; then
    INSTALL_PATH="${HOME}${APP_PATH}"
  elif [[ -d "${APP_PATH}" ]]; then
    INSTALL_PATH="${APP_PATH}"
  else
    echo -e "\nSpotify not found. Exiting…\n"; exit 1
  fi
else
  [[ -d "${APP_PATH}" ]] || { echo -e "\nSpotify not found. Exiting…\n"; exit 1; }
  INSTALL_PATH="${APP_PATH}"
fi

XPUI_PATH="${INSTALL_PATH}/Contents/Resources/Apps"
APP_BINARY="${INSTALL_PATH}/Contents/MacOS/Spotify"
APP_BINARY_BAK="${INSTALL_PATH}/Contents/MacOS/Spotify.bak"

###############################################################################
# 4 ── Snapshot-layout vars
###############################################################################
SNAPSHOT_MODE=false                 # path for xpui-modules.js will be set later

XPUI_DIR="${XPUI_PATH}/xpui"
XPUI_BAK="${XPUI_PATH}/xpui.bak"
XPUI_SPA="${XPUI_PATH}/xpui.spa"
XPUI_JS="${XPUI_DIR}/xpui.js"
XPUI_CSS="${XPUI_DIR}/xpui.css"
VENDOR_XPUI_JS="${XPUI_DIR}/vendor~xpui.js"
XPUI_DESKTOP_MODAL_JS="${XPUI_DIR}/xpui-desktop-modals.js"


###############################################################################
# 5 ── Uninstall branch
###############################################################################
if $UNINSTALL_FLAG; then
  if [[ ! -f "${XPUI_BAK}" || ! -f "${APP_BINARY_BAK}" ]]; then
    echo "No backup found — this install is unpatched."; exit 0
  fi
  echo "Restoring original files…"
  rm -f "${XPUI_SPA}" "${APP_BINARY}"
  mv "${XPUI_BAK}" "${XPUI_SPA}"
  mv "${APP_BINARY_BAK}" "${APP_BINARY}"
  echo "BlockTheSpot-Mac uninstalled."
  exit 0
fi

###############################################################################
# 6 ── Version & architecture checks
###############################################################################
CLIENT_VERSION=$(defaults read "${INSTALL_PATH}/Contents/Info.plist" CFBundleVersion)
MAC_ARCH=$(uname -m)

vercmp() {                       # decimal-safe: 1.2.3.4 → 1 002 003 004
  IFS=. read -r a b c d <<< "$1"
  printf '%d%03d%03d%03d\n' "$a" "$b" "$c" "$d"
}

MIN_VER="1.1.70.610"; MAX_VER="1.2.64.999"
if (( 10#$(vercmp "$CLIENT_VERSION") < 10#$(vercmp "$MIN_VER") || \
      10#$(vercmp "$CLIENT_VERSION") > 10#$(vercmp "$MAX_VER") )); then
    echo "Spotify $CLIENT_VERSION outside supported range ${MIN_VER}-${MAX_VER}."
    exit 1
fi


###############################################################################
# 7 ── Perl shorthand and regex payloads
###############################################################################
PERL='perl -pi -w -e'

# ── Ad-related regex
AD_EMPTY_AD_BLOCK='s|adsEnabled:!0|adsEnabled:!1|'
AD_PLAYLIST_SPONSORS='s|allSponsorships||'
AD_SPONSORS='s/ht.{14}\...\..{7}\....\/.{8}ap4p\/|ht.{14}\...\..{7}\....\/s.{15}t\/v.\///g'
AD_BILLBOARD='s|.(?=\?\[.{1,6}[a-zA-Z].leaderboard,)|false|'
AD_UPSELL='s|Enables quicksilver in-app messaging modal",default:\K!.(?=})|false|s'
AD_ADS='s#/a\Kd(?=s/v1)|/a\Kd(?=s/v2/t)|/a\Kd(?=s/v2/se)#b#gs'
AD_SERV='s|(this\._product_state(?:_service)?=(.))|$1,$2.putOverridesValues({pairs:{ads:'\''0'\'',catalogue:'\''premium'\'',product:'\''premium'\'',type:'\''premium'\''}})|'
AD_PATCH_1='s|\x00\K\x61(?=\x64\x2D\x6C\x6F\x67\x69\x63\x2F\x73)|\x00|'
AD_PATCH_2='s|\x00\K\x73(?=\x6C\x6F\x74\x73\x00)|\x00|'
AD_PATCH_3='s|\x70\x6F\x64\x63\x61\x73\x74\K\x2D\x70|\x20\x70|g'
AD_PATCH_4='s|\x70\x6F\x64\x63\x61\x73\x74\K\x2D\x6D\x69|\x20\x6D\x69|g'
AD_PATCH_5='s|\x00\K\x67(?=\x61\x62\x6F\x2D\x72\x65\x63\x65\x69\x76\x65\x72\x2D\x73\x65\x72\x76\x69\x63\x65)|\x00|g'
HPTO_ENABLED='s|hptoEnabled:!\K0|1|s'
HPTO_PATCH='s|(ADS_PREMIUM,isPremium:)\w(.*?ADS_HPTO_HIDDEN,isHptoHidden:)\w|$1true$2true|'

# ── Hide premium-only UI
HIDE_DL_QUALITY='s|return \K([^;]+?)(?=\?null[^}]+?desktop\.settings\.downloadQuality\.title)|true|'
HIDE_DL_ICON=' .BKsbV2Xl786X9a09XROH {display:none}'
HIDE_DL_MENU=' button.wC9sIed7pfp47wZbmU6m.pzkhLqffqF_4hucrVVQA {display:none}'
HIDE_VERY_HIGH=' #desktop\.settings\.streamingQuality>option:nth-child(5) {display:none}'

# ── Hide podcasts on home screen
HIDE_PODCASTS3='s/(!Array.isArray\(.\)\|\|.===..length)/$1||e[0].key.includes('\''episode'\'')||e[0].key.includes('\''show'\'')/'

# ── Credits modal
MODAL_CREDITS='s;((..createElement|children:\(.{1,7}\))\(.{1,7},\{source:).{1,7}get\("about.copyright",.\),paragraphClassName:.(?=\}\));$1"<h3>About BlockTheSpot-Mac</h3><br><a href='\''https://github.com/Nuzair46/BlockTheSpot-Mac'\''><svg xmlns='\''http://www.w3.org/2000/svg'\'' width='\''20'\'' height='\''20'\'' viewBox='\''0 0 24 24'\''><path d='\''M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z'\'' fill='\''#fff'\''/></svg> Nuzair46/BlockTheSpot-Mac</a><br><a href='https://discord.gg/eYudMwgYtY'><svg xmlns='\''http://www.w3.org/2000/svg'\'' width='\''20'\'' height='\''20'\'' viewBox='\''0 0 24 24'\''><path id='\''discord'\'' d='\''M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z'\'' fill='\''#fff'\''/></svg> BlockTheSpot Discord</a><br><a href='https://github.com/mrpond/BlockTheSpot'><svg fill='\''#fff'\'' width='\''20'\'' height='\''20'\'' viewBox='\''0 0 24 24'\'' xmlns='\''http://www.w3.org/2000/svg'\''><path id='\''windows'\'' d='\''m9.84 12.663v9.39l-9.84-1.356v-8.034zm0-10.72v9.505h-9.84v-8.145zm14.16 10.72v11.337l-13.082-1.803v-9.534zm0-12.663v11.452h-13.082v-9.649z'\''/></svg> For Windows 10/11</a><br><br>BlockTheSpot-Mac is provided \"as-is\" with no warranties. Use at your own risk. The BlockTheSpot team is not responsible. <a href='\''https://github.com/Nuzair46/BlockTheSpot-Mac/blob/main/LICENSE'\''>More info</a>.<br><br>Spotify&reg; is a registered trademark of Spotify Group.";'

# ── Telemetry
LOG_1='s|sp://logging/v3/\w+||g'
LOG_SENTRY='s|this\.getStackTop\(\)\.client=e|return;$&|'

# ── Updates
UPDATE_PATCH='s|\x64(?=\x65\x73\x6B\x74\x6F\x70\x2D\x75\x70)|\x00|g'

# ── Developer mode patch
if [[ "${MAC_ARCH}" == "arm64" ]]; then
  DEVELOPER_MODE_PATCH='s|\xF8\xFF[\x37\x77\xF7][\x06\x07\x08]\x39\xFF.[\x00\x04]\xB9\xE1[\x03\x43\xC3][\x06\x07\x08]\x91\xE2.[\x02\x03\x13]\x91\K..\x00\x94(?=[\xF7\xF8]\x03)|\x60\x00\x80\xD2|'
else
  DEVELOPER_MODE_PATCH='s|\xFF\xFF\x48\xB8\x65\x76\x65.{5}\x48.{36,40}\K\xE8.{2}(?=\x00\x00)|\xB8\x03\x00|'
fi

###############################################################################
# 8 ── Banner
###############################################################################
echo -e "\n************************"
echo "BlockTheSpot-Mac by @Nuzair46"
echo "************************\n"
echo "Spotify version:        $CLIENT_VERSION"
echo "BlockTheSpot-Mac build: $BLOCKTHESPOT_VERSION"
echo

###############################################################################
# 9 ── codesign presence
###############################################################################
if ! $SKIP_CODE_SIGNATURE && ! command -v codesign &>/dev/null; then
  echo "codesign missing. Install Xcode CLT or rerun with -S to skip."
  exit 1
fi

###############################################################################
# 10 ── Backup / integrity checks
###############################################################################
XPUI_SKIP=false
if [[ ! -f "${XPUI_SPA}" ]]; then
  echo -e "\nxpui.spa not found — reinstall Spotify.\n"; exit 1
fi

if ! $FORCE_FLAG; then
  if [[ -f "${XPUI_BAK}" || -f "${APP_BINARY_BAK}" ]]; then
    echo "BlockTheSpot backup found; use -f to force re-patch."
    XPUI_SKIP=true
  else
    echo "Creating backup…"
    cp "${XPUI_SPA}"   "${XPUI_BAK}"
    cp "${APP_BINARY}" "${APP_BINARY_BAK}"
  fi
else
  if [[ -f "${XPUI_BAK}" || -f "${APP_BINARY_BAK}" ]]; then
    echo "Restoring pristine files from backup…"
    rm -f "${XPUI_SPA}" "${APP_BINARY}"
    cp "${XPUI_BAK}"   "${XPUI_SPA}"
    cp "${APP_BINARY_BAK}" "${APP_BINARY}"
  else
    echo "Creating backup…"
    cp "${XPUI_SPA}"   "${XPUI_BAK}"
    cp "${APP_BINARY}" "${APP_BINARY_BAK}"
  fi
fi

###############################################################################
# 11 ── Extract xpui & detect snapshot layout
###############################################################################
if ! $XPUI_SKIP; then
  echo "Extracting xpui…"
  unzip -qq "${XPUI_SPA}" -d "${XPUI_DIR}"

  if [[ ! -f "${XPUI_DIR}/xpui.js" ]]; then
    echo "Snapshot layout detected."
    SNAPSHOT_MODE=true
  fi

  if $SNAPSHOT_MODE; then
    XPUI_MOD_JS="${XPUI_DIR}/xpui-modules.js"          # ← new correct path
    ./snapshot.sh "${INSTALL_PATH}" "${XPUI_MOD_JS}"
    cp "${XPUI_DIR}/xpui-snapshot.js" "${XPUI_DIR}/xpui-snapshot-orig.js"
    # inject loader tag so xpui-modules.js is loaded first
    $SED -i 's|<script src="xpui-snapshot.js"|<script src="xpui-modules.js"></script>\n&|' \
          "${XPUI_DIR}/index.html"
    XPUI_JS="${XPUI_MOD_JS}"
  fi

  if grep -Fq "BlockTheSpot" "${XPUI_JS}"; then
    echo -e "\nDetected previous patches without backup — aborting.\n"
    XPUI_SKIP=true
    rm -f "${XPUI_BAK}"; rm -rf "${XPUI_DIR}"
  else
    rm -f "${XPUI_SPA}"
  fi
fi

TARGET_JS="${XPUI_JS}"   # always patch the correct JS

###############################################################################
# 12 ── Patching phase
###############################################################################
echo "Applying BlockTheSpot patches…"

# ── 12-A  ad removal, binary tweaks, premium-UI strip ─────────────────────────
if ! $XPUI_SKIP; then
  echo "Stripping ad code…"
  $PERL "${AD_ADS}"               "${TARGET_JS}"
  $PERL "${AD_BILLBOARD}"         "${TARGET_JS}"
  $PERL "${AD_EMPTY_AD_BLOCK}"    "${TARGET_JS}"
  $PERL "${AD_SERV}"              "${TARGET_JS}"
  $PERL "${AD_PLAYLIST_SPONSORS}" "${TARGET_JS}"
  $PERL "${AD_UPSELL}"            "${TARGET_JS}"
  $PERL "${AD_SPONSORS}"          "${TARGET_JS}"
  $PERL "${HPTO_ENABLED}"         "${TARGET_JS}"
  $PERL "${HPTO_PATCH}"           "${TARGET_JS}"

  echo "Patching binary…"
  $PERL "${AD_ADS}"     "${APP_BINARY}"
  $PERL "${AD_PATCH_1}" "${APP_BINARY}"
  $PERL "${AD_PATCH_2}" "${APP_BINARY}"
  $PERL "${AD_PATCH_3}" "${APP_BINARY}"
  $PERL "${AD_PATCH_4}" "${APP_BINARY}"
  $PERL "${AD_PATCH_5}" "${APP_BINARY}"

  echo "Removing premium-only UI…"
  $PERL "${HIDE_DL_QUALITY}" "${TARGET_JS}"
  echo "${HIDE_DL_ICON}"   >> "${XPUI_CSS}"
  echo "${HIDE_DL_MENU}"   >> "${XPUI_CSS}"
  echo "${HIDE_VERY_HIGH}" >> "${XPUI_CSS}"
fi

# ── 12-B  optional developer mode ────────────────────────────────────────────
if $DEVELOPER_MODE; then
  echo "Enabling developer mode…"
  $PERL "${DEVELOPER_MODE_PATCH}" "${APP_BINARY}"
fi

# ── 12-C  telemetry strip + credits modal (guards for snapshot layout) ───────
if ! $XPUI_SKIP; then
  echo "Stripping telemetry…"
  $PERL "${LOG_1}" "${TARGET_JS}"
  [[ -f "${VENDOR_XPUI_JS}" ]] && \
      $PERL "${LOG_SENTRY}" "${VENDOR_XPUI_JS}"


  if [[ -f "${XPUI_DESKTOP_MODAL_JS}" ]]; then
    echo "Injecting credits modal…"
    $PERL "${MODAL_CREDITS}" "${XPUI_DESKTOP_MODAL_JS}"
  fi

  # ── 12-D  optional podcast/episode/audiobook hide ──────────────────────────
  if $HIDE_PODCASTS_FLAG && \
     [[ 10#$(vercmp "$CLIENT_VERSION") -ge 10#$(vercmp "1.1.98.683") ]]; then
    echo "Hiding podcasts / episodes / audiobooks on home screen…"
    $PERL "${HIDE_PODCASTS3}" "${TARGET_JS}"
  fi
fi

# ── 12-E  optional update blocker ────────────────────────────────────────────
if $UPDATE_FLAG; then
  echo "Blocking auto-updates…"
  $PERL "${UPDATE_PATCH}" "${APP_BINARY}"
fi

###############################################################################
# 13 ── Re-package xpui & sign
###############################################################################
if ! $XPUI_SKIP; then
  ( cd "${XPUI_DIR}" && zip -qq -r ../xpui.spa . )
  rm -rf "${XPUI_DIR}"
fi

echo "Code-signing Spotify…"
codesign -f --deep -s - "${APP_PATH}" &>/dev/null

echo -e "\nBlockTheSpot patch complete.\n"
