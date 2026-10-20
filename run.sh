#!/usr/bin/env bash
# ==============================================================================
# TiviPlayer TV - Universal Cross-Platform Build & Run Automation Script
# Supports: Android, macOS, Web, iOS (Debug, Profile, Release)
# ==============================================================================

set -eo pipefail

# ANSI Color Codes for Rich Terminal Aesthetics
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Determine project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/pubspec.yaml" ]; then
    PROJECT_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/tv_player_app/pubspec.yaml" ]; then
    PROJECT_DIR="$SCRIPT_DIR/tv_player_app"
else
    echo -e "${RED}Error: Cannot locate tv_player_app project directory containing pubspec.yaml.${NC}"
    exit 1
fi

cd "$PROJECT_DIR"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    echo "  ████████╗██╗██╗   ██╗██╗██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗ "
    echo "  ╚══██╔══╝██║██║   ██║██║██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗"
    echo "     ██║   ██║██║   ██║██║██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝"
    echo "     ██║   ██║╚██╗ ██╔╝██║██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗"
    echo "     ██║   ██║ ╚████╔╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║"
    echo "     ╚═╝   ╚═╝  ╚═══╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "   ${PURPLE}${BOLD}Cross-Platform Live TV Player Automation Engine${NC}"
    echo -e "   ${DIM}Root: $PROJECT_DIR${NC}"
    echo "--------------------------------------------------------------------------------"
}

check_flutter() {
    if ! command -v flutter &>/dev/null; then
        echo -e "${RED}${BOLD}[ERROR]${NC} Flutter SDK was not found in your PATH."
        echo -e "Please ensure Flutter is installed and added to PATH."
        exit 1
    fi
}

ensure_deps() {
    if [ ! -d ".dart_tool" ] || [ ! -f "pubspec.lock" ]; then
        echo -e "${YELLOW}Resolving Flutter dependencies first...${NC}"
        flutter pub get
    fi
}

check_or_launch_android_emulator() {
    echo -e "${BLUE}Checking connected Android devices...${NC}"
    local online_devices
    online_devices=$(adb devices 2>/dev/null | grep -w "device" | grep -v "List" || true)

    if [ -z "$online_devices" ]; then
        echo -e "${YELLOW}No active Android device detected.${NC}"
        echo -e "${CYAN}Looking for available Android emulators...${NC}"
        local emu_id
        emu_id=$(flutter emulators 2>/dev/null | grep "android" | awk -F '•' '{print $1}' | tr -d ' ' | head -n 1 || true)
        
        if [ -n "$emu_id" ]; then
            echo -e "${GREEN}Launching emulator: ${BOLD}$emu_id${NC}..."
            flutter emulators --launch "$emu_id"
            echo -e "${YELLOW}Waiting for emulator to complete boot...${NC}"
            adb wait-for-device
            local booted=""
            for _ in {1..30}; do
                booted=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
                if [ "$booted" = "1" ]; then
                    break
                fi
                sleep 2
            done
            echo -e "${GREEN}Android emulator is online and ready!${NC}"
        else
            echo -e "${RED}No Android emulator found. Please start an emulator or connect a device via ADB.${NC}"
        fi
    else
        echo -e "${GREEN}Detected online Android device/emulator:${NC}"
        echo "$online_devices"
    fi
}

# ------------------------------------------------------------------------------
# Action Functions
# ------------------------------------------------------------------------------
do_run() {
    local platform="$1"
    local mode="${2:-debug}"

    check_flutter
    ensure_deps

    local run_args=()
    local mode_upper
    case "$mode" in
        release) run_args+=("--release"); mode_upper="RELEASE" ;;
        profile) run_args+=("--profile"); mode_upper="PROFILE" ;;
        debug|*)  run_args+=("--debug"); mode_upper="DEBUG" ;;
    esac

    case "$platform" in
        android)
            check_or_launch_android_emulator
            echo -e "${GREEN}${BOLD}>>> Starting TiviPlayer on Android [Mode: ${mode_upper}]...${NC}"
            flutter run -d android "${run_args[@]}"
            ;;
        macos|desktop)
            echo -e "${GREEN}${BOLD}>>> Starting TiviPlayer on macOS Desktop [Mode: ${mode_upper}]...${NC}"
            flutter run -d macos "${run_args[@]}"
            ;;
        web|chrome)
            local port="${3:-8080}"
            echo -e "${GREEN}${BOLD}>>> Starting TiviPlayer on Chrome/Web (Port: $port) [Mode: ${mode_upper}]...${NC}"
            flutter run -d chrome --web-port="$port" "${run_args[@]}"
            ;;
        ios)
            echo -e "${GREEN}${BOLD}>>> Starting TiviPlayer on iOS Simulator [Mode: ${mode_upper}]...${NC}"
            flutter run -d ios "${run_args[@]}"
            ;;
        *)
            echo -e "${RED}Unknown run target: $platform. Use: android, macos, web, ios${NC}"
            exit 1
            ;;
    esac
}

build_macos_dmg() {
    local mode="${1:-release}"
    local mode_dir="Release"
    if [ "$mode" = "debug" ]; then
        mode_dir="Debug"
    elif [ "$mode" = "profile" ]; then
        mode_dir="Profile"
    fi

    if [ "$(uname -s)" != "Darwin" ]; then
        echo -e "${YELLOW}[NOTE] macOS .dmg packaging requires macOS (hdiutil). Skipping on $(uname -s).${NC}"
        return 0
    fi

    local products_dir="build/macos/Build/Products/$mode_dir"
    local app_path
    app_path=$(ls -d "$products_dir/"*.app 2>/dev/null | head -n 1 || true)

    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        app_path=$(ls -d build/macos/Build/Products/*/*.app 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        echo -e "${RED}[ERROR] macOS .app bundle not found in $products_dir. Run flutter build macos first.${NC}"
        return 1
    fi

    local app_name
    app_name=$(basename "$app_path" .app)
    local dmg_filename="${app_name}.dmg"
    local output_dir="$PROJECT_DIR/build/macos/outputs"
    mkdir -p "$output_dir"
    local target_dmg="$output_dir/$dmg_filename"
    local product_dmg="$(dirname "$app_path")/$dmg_filename"

    echo -e "\n${BLUE}${BOLD}>>> Packaging $app_name into macOS Installer Disk Image (.dmg)...${NC}"

    local staging_dir
    staging_dir=$(mktemp -d /tmp/tiviplayer_dmg_staging.XXXXXX)

    echo -e "${DIM}Preparing DMG staging layout (App bundle + Applications shortcut)...${NC}"
    cp -R "$app_path" "$staging_dir/"
    ln -s /Applications "$staging_dir/Applications"

    rm -f "$target_dmg" "$product_dmg"

    if command -v create-dmg &>/dev/null; then
        echo -e "${CYAN}Creating DMG using create-dmg utility...${NC}"
        create-dmg \
            --volname "$app_name" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "$app_name.app" 150 190 \
            --app-drop-link 450 190 \
            --hide-extension "$app_name.app" \
            --no-internet-enable \
            "$target_dmg" \
            "$staging_dir" 2>/dev/null || {
                echo -e "${YELLOW}create-dmg failed, falling back to native hdiutil...${NC}"
                hdiutil create -volname "$app_name" -srcfolder "$staging_dir" -ov -format UDZO "$target_dmg"
            }
    else
        echo -e "${CYAN}Packaging DMG with native macOS hdiutil (UDZO compressed)...${NC}"
        hdiutil create -volname "$app_name" -srcfolder "$staging_dir" -ov -format UDZO "$target_dmg"
    fi

    rm -rf "$staging_dir"

    # Keep a copy directly in Products folder alongside the .app
    cp -f "$target_dmg" "$product_dmg" 2>/dev/null || true

    echo -e "\n${GREEN}${BOLD}[✓] macOS DMG Installer Created Successfully!${NC}"
    echo -e " • ${BOLD}DMG Installer:${NC} $target_dmg"
    ls -lh "$target_dmg"
    echo -e " • ${DIM}Products Copy:${NC} $product_dmg"
}

do_build() {
    local target="$1"
    local mode="${2:-release}"

    check_flutter
    ensure_deps

    local mode_upper
    local build_flag=""
    if [ "$mode" = "debug" ]; then
        build_flag="--debug"
        mode_upper="DEBUG"
    elif [ "$mode" = "profile" ]; then
        build_flag="--profile"
        mode_upper="PROFILE"
    else
        build_flag="--release"
        mode_upper="RELEASE"
    fi

    case "$target" in
        apk)
            echo -e "${GREEN}${BOLD}>>> Building Android APK [${mode_upper}]...${NC}"
            flutter build apk $build_flag
            echo -e "\n${CYAN}${BOLD}[✓] APK Build Complete:${NC}"
            ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
            ;;
        bundle|aab)
            echo -e "${GREEN}${BOLD}>>> Building Android App Bundle (AAB) [${mode_upper}]...${NC}"
            flutter build appbundle $build_flag
            echo -e "\n${CYAN}${BOLD}[✓] Bundle Build Complete:${NC}"
            ls -lh build/app/outputs/bundle/*/*.aab 2>/dev/null || true
            ;;
        dmg)
            local mode_dir="Release"
            [ "$mode" = "debug" ] && mode_dir="Debug"
            [ "$mode" = "profile" ] && mode_dir="Profile"
            if [ ! -d "build/macos/Build/Products/$mode_dir" ] || [ -z "$(ls -d build/macos/Build/Products/$mode_dir/*.app 2>/dev/null)" ]; then
                echo -e "${YELLOW}macOS .app not found. Running flutter build macos $build_flag first...${NC}"
                flutter build macos $build_flag
            fi
            build_macos_dmg "$mode"
            ;;
        macos|desktop)
            echo -e "${GREEN}${BOLD}>>> Building macOS Application [${mode_upper}]...${NC}"
            flutter build macos $build_flag
            echo -e "\n${CYAN}${BOLD}[✓] macOS App Build Complete:${NC}"
            ls -d build/macos/Build/Products/*/*.app 2>/dev/null || true
            build_macos_dmg "$mode"
            ;;
        web)
            echo -e "${GREEN}${BOLD}>>> Building Production Web Bundle...${NC}"
            flutter build web --release
            echo -e "\n${CYAN}${BOLD}[✓] Web Build Complete:${NC}"
            echo -e "Deployable artifacts ready in: ${BOLD}$PROJECT_DIR/build/web/${NC}"
            ;;
        ios)
            echo -e "${GREEN}${BOLD}>>> Building iOS App (No Code-Sign)...${NC}"
            flutter build ios --no-codesign $build_flag
            echo -e "\n${CYAN}${BOLD}[✓] iOS Build Complete:${NC}"
            ls -d build/ios/iphoneos/*.app 2>/dev/null || true
            ;;
        all)
            echo -e "${PURPLE}${BOLD}=================================================================${NC}"
            echo -e "${PURPLE}${BOLD}>>> Executing Multi-Platform Build: Android + macOS + Web       ${NC}"
            echo -e "${PURPLE}${BOLD}=================================================================${NC}"
            
            echo -e "\n${CYAN}[1/3] Building Android Release APK...${NC}"
            flutter build apk --release
            
            echo -e "\n${CYAN}[2/3] Building macOS Desktop App & DMG...${NC}"
            flutter build macos --release
            build_macos_dmg "release"
            
            echo -e "\n${CYAN}[3/3] Building Web Distribution...${NC}"
            flutter build web --release

            echo -e "\n${GREEN}${BOLD}=================================================================${NC}"
            echo -e "${GREEN}${BOLD}✓ ALL PLATFORM BUILDS COMPLETED SUCCESSFULLY!                    ${NC}"
            echo -e "${GREEN}${BOLD}=================================================================${NC}"
            echo -e " • ${BOLD}Android APK:${NC}  $(ls build/app/outputs/flutter-apk/*-release.apk 2>/dev/null || echo 'build/app/outputs/flutter-apk/')"
            echo -e " • ${BOLD}macOS App:${NC}    $(ls -d build/macos/Build/Products/Release/*.app 2>/dev/null || echo 'build/macos/Build/Products/Release/')"
            echo -e " • ${BOLD}macOS DMG:${NC}    $(ls build/macos/outputs/*.dmg 2>/dev/null || echo 'build/macos/outputs/')"
            echo -e " • ${BOLD}Web App:${NC}      $PROJECT_DIR/build/web/"
            ;;
        *)
            echo -e "${RED}Unknown build target: $target. Use: apk, bundle, macos, dmg, web, ios, all${NC}"
            exit 1
            ;;
    esac
}

do_install_android() {
    local mode="${1:-debug}"
    check_flutter
    check_or_launch_android_emulator

    local apk_path=""
    if [ "$mode" = "release" ]; then
        apk_path="build/app/outputs/flutter-apk/app-release.apk"
    else
        apk_path="build/app/outputs/flutter-apk/app-debug.apk"
    fi

    if [ ! -f "$apk_path" ]; then
        echo -e "${YELLOW}APK not found at $apk_path. Building now...${NC}"
        do_build apk "$mode"
    fi

    echo -e "${GREEN}Installing $apk_path via ADB...${NC}"
    adb install -r "$apk_path"
    echo -e "${GREEN}Launching app on device...${NC}"
    adb shell am start -n com.app.tvplayer.tv_player_app/.MainActivity
}

do_clean() {
    check_flutter
    echo -e "${YELLOW}Cleaning Flutter project caches and generated files...${NC}"
    flutter clean
    echo -e "${GREEN}Fetching fresh dependencies...${NC}"
    flutter pub get
    echo -e "${GREEN}${BOLD}Project is clean and dependencies are refreshed!${NC}"
}

do_doctor() {
    check_flutter
    flutter doctor -v
}

# ------------------------------------------------------------------------------
# Interactive Menu
# ------------------------------------------------------------------------------
interactive_menu() {
    while true; do
        print_banner
        echo -e "${BOLD}▶ RUN APP (Interactive / Hot Reload):${NC}"
        echo -e "  ${GREEN}1)${NC} Run on Android Device / Emulator    ${DIM}(Debug)${NC}"
        echo -e "  ${GREEN}2)${NC} Run on Android Device / Emulator    ${DIM}(Release)${NC}"
        echo -e "  ${GREEN}3)${NC} Run on macOS Desktop                ${DIM}(Debug - libmpv)${NC}"
        echo -e "  ${GREEN}4)${NC} Run on macOS Desktop                ${DIM}(Release)${NC}"
        echo -e "  ${GREEN}5)${NC} Run on Chrome / Web                 ${DIM}(Debug - Shaka Player)${NC}"
        echo -e "  ${GREEN}6)${NC} Run on iOS Simulator                ${DIM}(Debug)${NC}"
        echo ""
        echo -e "${BOLD}▶ BUILD APP PACKAGES:${NC}"
        echo -e "  ${CYAN}7)${NC} Build Android APK                   ${DIM}(Release)${NC}"
        echo -e "  ${CYAN}8)${NC} Build Android APK                   ${DIM}(Debug)${NC}"
        echo -e "  ${CYAN}9)${NC} Build Android App Bundle (.aab)     ${DIM}(Play Store)${NC}"
        echo -e " ${CYAN}10)${NC} Build macOS App & DMG (.dmg)        ${DIM}(Release)${NC}"
        echo -e " ${CYAN}11)${NC} Build Web Distribution              ${DIM}(build/web/)${NC}"
        echo -e " ${CYAN}12)${NC} Build ALL Platforms                 ${DIM}(Android + macOS + Web)${NC}"
        echo ""
        echo -e "${BOLD}▶ UTILITIES & TOOLS:${NC}"
        echo -e " ${PURPLE}13)${NC} Install & Launch on Android Device  ${DIM}(ADB Streamed Install)${NC}"
        echo -e " ${PURPLE}14)${NC} Launch Android Emulator             ${DIM}(Pixel 9 / AVD)${NC}"
        echo -e " ${PURPLE}15)${NC} Clean & Refresh Dependencies        ${DIM}(flutter clean && pub get)${NC}"
        echo -e " ${PURPLE}16)${NC} Flutter Doctor Diagnostic           ${DIM}(Environment Check)${NC}"
        echo ""
        echo -e "  ${RED}0)${NC} Exit"
        echo "--------------------------------------------------------------------------------"
        read -rp "Select an option [0-16]: " choice

        case "$choice" in
            1)  do_run android debug; read -rp "Press Enter to return..." ;;
            2)  do_run android release; read -rp "Press Enter to return..." ;;
            3)  do_run macos debug; read -rp "Press Enter to return..." ;;
            4)  do_run macos release; read -rp "Press Enter to return..." ;;
            5)  do_run web debug; read -rp "Press Enter to return..." ;;
            6)  do_run ios debug; read -rp "Press Enter to return..." ;;
            7)  do_build apk release; read -rp "Press Enter to return..." ;;
            8)  do_build apk debug; read -rp "Press Enter to return..." ;;
            9)  do_build bundle release; read -rp "Press Enter to return..." ;;
            10) do_build macos release; read -rp "Press Enter to return..." ;;
            11) do_build web release; read -rp "Press Enter to return..." ;;
            12) do_build all release; read -rp "Press Enter to return..." ;;
            13) do_install_android debug; read -rp "Press Enter to return..." ;;
            14) check_or_launch_android_emulator; read -rp "Press Enter to return..." ;;
            15) do_clean; read -rp "Press Enter to return..." ;;
            16) do_doctor; read -rp "Press Enter to return..." ;;
            0|q|Q) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

print_help() {
    echo -e "${BOLD}Usage:${NC} ./run.sh [command] [target] [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  (no arguments)              Launch interactive menu"
    echo "  run <platform> [mode]       Run app on target platform (debug, release, profile)"
    echo "                              Platforms: android, macos, web, ios"
    echo "  build <target> [mode]       Build platform package (release by default)"
    echo "                              Targets: apk, bundle, macos, dmg, web, ios, all"
    echo "  install [debug|release]     Install APK on connected Android device and launch"
    echo "  clean                       Clean build caches and refresh pub dependencies"
    echo "  emulator                    Launch available Android emulator"
    echo "  doctor                      Run flutter doctor diagnostic"
    echo "  help                        Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./run.sh                    # Interactive menu"
    echo "  ./run.sh run android        # Run on Android in debug mode"
    echo "  ./run.sh run macos release  # Run on macOS in release mode"
    echo "  ./run.sh run web            # Run on Chrome web browser"
    echo "  ./run.sh build apk          # Build release Android APK"
    echo "  ./run.sh build macos        # Build macOS App and installer DMG (.dmg)"
    echo "  ./run.sh build dmg          # Build macOS DMG installer disk image directly"
    echo "  ./run.sh build all          # Build Android APK, macOS App & DMG, and Web bundle"
    echo "  ./run.sh install            # Build and deploy directly to phone/emulator"
}

# ------------------------------------------------------------------------------
# Entrypoint Router
# ------------------------------------------------------------------------------
if [ $# -eq 0 ]; then
    interactive_menu
else
    COMMAND="$1"
    shift
    case "$COMMAND" in
        run)
            do_run "$1" "$2" "$3"
            ;;
        build)
            do_build "$1" "$2"
            ;;
        install)
            do_install_android "$1"
            ;;
        clean)
            do_clean
            ;;
        emulator)
            check_or_launch_android_emulator
            ;;
        doctor)
            do_doctor
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            echo -e "${RED}Unknown command: $COMMAND${NC}"
            print_help
            exit 1
            ;;
    esac
fi
