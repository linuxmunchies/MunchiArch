#!/bin/bash

# ===================================================================
# Arch Linux Setup Script - Vimmarch Version
# ===================================================================

set -euo pipefail # Exit on error, undefined vars, pipe failures

# ===================================================================
# CONFIGURATION
# ===================================================================

readonly SCRIPT_VERSION="4.0.0"
# --- Use the SUDO_USER or logname, fail if user cannot be determined
readonly ACTUAL_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
readonly ACTUAL_HOME="/home/${ACTUAL_USER}"
readonly LOG_FILE="${ACTUAL_HOME}/Desktop/arch_setup.log"
readonly CONFIG_DIR="${ACTUAL_HOME}/.config/arch-setup"
readonly BACKUP_DIR="/var/backups/arch-setup"

# --- System Configuration ---
readonly TIMEZONE="America/Chicago"
readonly REFLECTOR_COUNTRIES=("United States" "Canada" "Mexico" "United Kingdom" "Germany" "France")

# --- Directory Creation ---
readonly DIRECTORIES_TO_CREATE=(
    "${ACTUAL_HOME}/ProtonDrive/Archives/Discord"
    "${ACTUAL_HOME}/ProtonDrive/Archives/Obsidian"
    "${ACTUAL_HOME}/ProtonDrive/Career/MainDocs"
    "${ACTUAL_HOME}/Development/Projects"
    "${ACTUAL_HOME}/Development/Scripts"
    "${ACTUAL_HOME}/.local/bin"
    "${ACTUAL_HOME}/.config/systemd/user"
)

# --- Dotfiles Configuration ---
readonly DOTFILES_REPO="https://github.com/linuxmunchies/dotfiles"
readonly DOTFILES_DIR="${ACTUAL_HOME}/.dotfiles"

# --- Game Drive Configuration ---
GAME_DRIVE_UUID=""
readonly GAME_DRIVE_MOUNT="/mnt/gamedrive"

# ===================================================================
# UTILITY FUNCTIONS
# ===================================================================

display_welcome_banner() {
    # Purple to Gold Gradient
    C1='\033[38;5;54m'  # Dark Purple
    C2='\033[38;5;93m'  # Purple
    C3='\033[38;5;162m' # Pinkish-Purple
    C4='\033[38;5;208m' # Orange
    C5='\033[38;5;220m' # Gold
    C_NC='\033[0m'      # No Color
    C_BOLD_GOLD='\033[1;38;5;220m'

    clear
    echo -e "${C1}VV    VV II MM    MM MM    MM  AA   RRRRRR    CCCCC  HH    HH${C_NC}"
    echo -e "${C2}VV    VV II MMM  MMM MMM  MMM AAAA  RR   RR  CC    C HH    HH${C_NC}"
    echo -e "${C3} VV  VV  II MM MM MM MM MM MM AA  AA RR   RR CC       HHHHHHHH${C_NC}"
    echo -e "${C4}  VVVV   II MM    MM MM    MM AAAAAA RRRRRR  CC    C HH    HH${C_NC}"
    echo -e "${C5}   VV    II MM    MM MM    MM AA  AA RR  RR   CCCCC  HH    HH${C_NC}"
    echo ""
    echo -e "    ${C_BOLD_GOLD}Welcome to the Vimmarch Arch Linux Setup!${C_NC}"
    echo -e "                 ${C_BOLD_GOLD}Version ${SCRIPT_VERSION}${C_NC}"
    echo ""
    echo "This script will guide you through setting up your Arch Linux system."
    echo ""
    sleep 3
}

# Logging function with levels
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    case "$level" in
    ERROR) echo -e "\033[31m[ERROR]\033[0m $timestamp - $message" | tee -a "$LOG_FILE" ;;
    WARN) echo -e "\033[33m[WARN]\033[0m $timestamp - $message" | tee -a "$LOG_FILE" ;;
    INFO) echo -e "\033[32m[INFO]\033[0m $timestamp - $message" | tee -a "$LOG_FILE" ;;
    DEBUG) echo -e "\033[36m[DEBUG]\033[0m $timestamp - $message" | tee -a "$LOG_FILE" ;;
    *) echo "$timestamp - $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Enhanced error handling
error_exit() {
    log ERROR "$1"
    exit "${2:-1}"
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percentage=$((current * 100 / total))

    printf "\r\033[K[%3d%%] (%d/%d) %s" "$percentage" "$current" "$total" "$description"
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Confirmation with timeout
confirm_with_timeout() {
    local prompt="$1"
    local timeout="${2:-30}"
    local default="${3:-n}"

    if [ -t 0 ]; then
        read -t "$timeout" -p "$prompt (y/n, default=$default in ${timeout}s): " response || response="$default"
    else
        response="$default"
    fi

    case "${response,,}" in
    y | yes) return 0 ;;
    *) return 1 ;;
    esac
}

# ===================================================================
# SYSTEM VALIDATION
# ===================================================================

validate_system() {
    log INFO "Validating system requirements..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi

    # Check if a user is determined
    if [[ -z "$ACTUAL_USER" ]]; then
        error_exit "Could not determine the non-root user. Please run with 'sudo -u your_user $0' or ensure logname is available."
    fi

    # Check if on Arch Linux
    if ! grep -q "Arch Linux" /etc/os-release; then
        error_exit "This script is designed for Arch Linux only"
    fi

    # Check internet connectivity
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error_exit "No internet connectivity detected"
    fi

    # Create necessary directories
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$CONFIG_DIR"

    # Initialize log file
    touch "$LOG_FILE"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$LOG_FILE"

    log INFO "System validation completed successfully"
}

# ===================================================================
# PACKAGE MANAGEMENT
# ===================================================================

# Enhanced package installation with retry logic
install_packages() {
    local packages=("$@")
    local failed_packages=()
    local max_retries=3

    log INFO "Installing packages: ${packages[*]}"

    for package in "${packages[@]}"; do
        local retry_count=0
        local success=false

        while [[ $retry_count -lt $max_retries ]]; do
            if pacman -S --needed --noconfirm "$package" &>>"$LOG_FILE"; then
                success=true
                break
            else
                ((retry_count++))
                log WARN "Failed to install $package, attempt $retry_count/$max_retries"
                sleep 2
            fi
        done

        if [[ $success == false ]]; then
            failed_packages+=("$package")
            log ERROR "Failed to install $package after $max_retries attempts"
        fi
    done

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log ERROR "Failed to install: ${failed_packages[*]}"
        return 1
    fi

    log INFO "All packages installed successfully"
    return 0
}

# AUR helper setup with error handling
setup_aur_helper() {
    log INFO "Setting up AUR helper (yay)..."

    if command -v yay &>/dev/null; then
        log INFO "yay is already installed"
        return 0
    fi

    # Install dependencies
    install_packages git base-devel

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN

    # Install yay as the actual user
    su - $ACTUAL_USER <<EOF
      git clone https://aur.archlinux.org/yay.git /tmp/yay-install
      cd /tmp/yay-install
      makepkg -si --noconfirm
EOF

    log INFO "yay installed successfully"
}

# Enhanced system upgrade
system_upgrade() {
    log INFO "Performing system upgrade..."
    pacman -Syu --noconfirm
    log INFO "System upgrade completed"
}

# ===================================================================
# MIRROR OPTIMIZATION
# ===================================================================

optimize_mirrors() {
    log INFO "Optimizing package mirrors..."

    local backup_file="$BACKUP_DIR/mirrorlist.$(date +%Y%m%d_%H%M%S)"
    local mirrorlist="/etc/pacman.d/mirrorlist"

    # Install reflector
    if ! command -v reflector &>/dev/null; then
        install_packages reflector
    fi

    # Backup current mirrorlist
    cp "$mirrorlist" "$backup_file"
    log INFO "Mirrorlist backed up to $backup_file"

    # Generate new mirrorlist
    if reflector \
        --protocol https \
        --country "${REFLECTOR_COUNTRIES[*]}" \
        --age 12 \
        --latest 20 \
        --sort rate \
        --save "$mirrorlist" &>>"$LOG_FILE"; then
        log INFO "Mirrorlist updated successfully"

        # Cleanup old backups (keep last 5)
        find "$BACKUP_DIR" -name "mirrorlist.*" -type f | sort -r | tail -n +6 | xargs -r rm -f
    else
        log ERROR "Reflector failed, restoring backup"
        cp "$backup_file" "$mirrorlist"
        return 1
    fi
}

# ===================================================================
# SYSTEM CONFIGURATION
# ===================================================================

configure_pacman() {
    log INFO "Configuring pacman..."

    local pacman_conf="/etc/pacman.conf"
    local backup_file="$BACKUP_DIR/pacman.conf.$(date +%Y%m%d_%H%M%S)"

    # Backup current configuration
    cp "$pacman_conf" "$backup_file"

    # Enable color output
    sed -i 's/^#Color/Color/' "$pacman_conf"

    # Enable parallel downloads
    if ! grep -q "^ParallelDownloads" "$pacman_conf"; then
        sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' "$pacman_conf"
    fi

    # Enable multilib repository
    if ! grep -A1 "^\[multilib\]" "$pacman_conf" | grep -q "Include"; then
        sed -i '/^\[multilib\]/,/Include/s/^#//' "$pacman_conf"
    fi

    log INFO "Pacman configuration updated"
}

setup_timezone() {
    log INFO "Setting timezone to $TIMEZONE..."

    if ! timedatectl set-timezone "$TIMEZONE"; then
        log ERROR "Failed to set timezone"
        return 1
    fi

    # Enable NTP synchronization
    timedatectl set-ntp true

    log INFO "Timezone configured successfully"
}

setup_firewall() {
    log INFO "Setting up UFW firewall..."
    install_packages ufw

    log INFO "Applying default firewall rules..."
    ufw default deny incoming &>>"$LOG_FILE"
    ufw default allow outgoing &>>"$LOG_FILE"
    ufw allow ssh &>>"$LOG_FILE"

    log INFO "Enabling firewall service..."
    systemctl enable --now ufw &>>"$LOG_FILE"

    log INFO "Firewall is active. Status:"
    ufw status verbose | tee -a "$LOG_FILE"
}

# ===================================================================
# GPU OPTIMIZATION
# ===================================================================

setup_gpu_optimization() {
    log INFO "Setting up GPU optimization..."
    local gpu_detected=false
    local modules=()

    # Robust AMD/ATI GPU detection
    if lspci | grep -Ei 'VGA|3D' | grep -E 'AMD|ATI|Advanced Micro Devices'; then
        log INFO "AMD GPU detected"
        modules+=("amdgpu")
        install_packages mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
        gpu_detected=true
    fi

    if lspci | grep -Ei 'VGA|3D' | grep -qi 'intel'; then
        log INFO "Intel GPU detected"
        modules+=("i915")
        install_packages mesa lib32-mesa vulkan-intel lib32-vulkan-intel
        gpu_detected=true
    fi

    if lspci | grep -Ei 'VGA|3D' | grep -qi 'nvidia'; then
        log INFO "NVIDIA GPU detected"
        log WARN "Consider installing NVIDIA drivers manually"
        gpu_detected=true
    fi

    if [[ $gpu_detected == false ]]; then
        log WARN "No discrete GPU detected"
        return 0
    fi

    # Configure early KMS for detected modules
    if [[ ${#modules[@]} -gt 0 ]]; then
        configure_early_kms "${modules[@]}"
    fi
}

configure_early_kms() {
    local modules=("$@")
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    local backup_file="$BACKUP_DIR/mkinitcpio.conf.$(date +%Y%m%d_%H%M%S)"

    log INFO "Configuring early KMS for modules: ${modules[*]}"

    # Backup configuration
    cp "$mkinitcpio_conf" "$backup_file"

    # Add modules to MODULES array
    for module in "${modules[@]}"; do
        if ! grep -q "^MODULES=.*\b$module\b" "$mkinitcpio_conf"; then
            sed -i "/^MODULES=/ s/)/ $module)/" "$mkinitcpio_conf"
            log INFO "Added $module to initramfs modules"
        fi
    done

    # Rebuild initramfs
    if mkinitcpio -P &>>"$LOG_FILE"; then
        log INFO "Initramfs rebuilt successfully"
    else
        log ERROR "Failed to rebuild initramfs, restoring backup"
        cp "$backup_file" "$mkinitcpio_conf"
        return 1
    fi
}

# ===================================================================
# STORAGE SETUP
# ===================================================================

setup_game_drive() {
    log INFO "Setting up game drive..."

    # Check if drive exists using blkid
    if ! blkid | grep -q "$GAME_DRIVE_UUID"; then
        log WARN "Game drive with UUID $GAME_DRIVE_UUID not detected, skipping"
        return 0
    fi

    # Get clean device path from blkid
    local device_path
    device_path=$(blkid -U "$GAME_DRIVE_UUID")

    if [[ -z "$device_path" ]]; then
        log ERROR "Could not determine device path for game drive"
        return 1
    fi

    log INFO "Found game drive at: $device_path"

    # Create mount point
    mkdir -p "$GAME_DRIVE_MOUNT"

    # BTRFS-specific optimizations
    local mount_options="defaults,noatime,space_cache=v2,compress=zstd:1,autodefrag"

    # Fix potential space cache issues
    log INFO "Checking BTRFS filesystem health..."
    if ! btrfs filesystem show "$device_path" &>/dev/null; then
        log ERROR "Device $device_path is not a valid BTRFS filesystem"
        return 1
    fi

    # Mount the drive
    if mount -t btrfs -o "$mount_options" "$device_path" "$GAME_DRIVE_MOUNT" &>>"$LOG_FILE"; then
        log INFO "Game drive mounted successfully"

        # Update fstab
        local fstab_entry="UUID=$GAME_DRIVE_UUID $GAME_DRIVE_MOUNT btrfs $mount_options 0 2"
        if ! grep -q "$GAME_DRIVE_UUID.*$GAME_DRIVE_MOUNT" /etc/fstab; then
            echo "$fstab_entry" >>/etc/fstab
            log INFO "Added game drive to fstab"
        fi

        # Set proper ownership
        chown "$ACTUAL_USER:$ACTUAL_USER" "$GAME_DRIVE_MOUNT"

    else
        log ERROR "Failed to mount game drive"
        return 1
    fi
}

# ===================================================================
# CPU/GPU/LAPTOP-SPECIFIC PACKAGE LOGIC
# ===================================================================

install_cpu_specific_packages() {
    case "$USER_CPU" in
    amd)
        log INFO "Installing AMD CPU microcode and tools..."
        install_packages amd-ucode cpupower
        ;;
    intel)
        log INFO "Installing Intel CPU microcode and tools..."
        install_packages intel-ucode thermald powertop
        ;;
    *)
        log INFO "No specific CPU microcode selected."
        ;;
    esac
}

install_gpu_specific_packages() {
    case "$USER_GPU" in
    amd)
        log INFO "Installing AMD GPU drivers..."
        install_packages mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu
        ;;
    intel)
        log INFO "Installing Intel GPU drivers..."
        install_packages mesa lib32-mesa vulkan-intel lib32-vulkan-intel xf86-video-intel
        ;;
    nvidia)
        log INFO "Installing NVIDIA GPU drivers..."
        install_packages nvidia nvidia-utils lib32-nvidia-utils nvidia-settings
        ;;
    *)
        log INFO "No specific GPU drivers selected."
        ;;
    esac
}

install_laptop_packages() {
    if [[ "$USER_LAPTOP" == "yes" ]]; then
        log INFO "Installing laptop-specific packages..."
        install_packages tlp acpi acpi_call acpid powertop iio-sensor-proxy
        systemctl enable --now tlp acpid
    fi
}

# ===================================================================
# APPLICATION INSTALLATION
# ===================================================================

setup_flatpak() {
    log INFO "Setting up Flatpak..."

    install_packages flatpak

    # Add Flathub repository
    if ! flatpak remote-list | grep -q flathub; then
        sudo -u "$ACTUAL_USER" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi

    # Update Flatpak
    sudo -u "$ACTUAL_USER" flatpak update -y &>>"$LOG_FILE"

    log INFO "Flatpak setup completed"
}

install_essential_apps() {
    if [[ ! " ${USER_STEPS[*]} " =~ essentials ]]; then
        log INFO "Skipping essential applications"
        return 0
    fi

    log INFO "Installing essential applications..."

    # System utilities
    local essential_packages=(
        man-db htop btop fastfetch git wget curl
        zip unzip unrar rsync fzf ncdu tmux
        vim neovim kitty wl-clipboard
        bluez-utils power-profiles-daemon
        partitionmanager exfatprogs
        intel-gpu-tools amdgpu_top
        flatpak bat make gcc go tldr zsh timeshift
        os-prober)

    install_packages "${essential_packages[@]}"

    # Essential Flatpaks
    local essential_flatpaks=(
        net.nokyan.Resources
        it.mijorus.gearlever
        com.bitwarden.desktop
        org.gnome.World.PikaBackup
        com.github.tchx84.Flatseal
        org.telegram.desktop
        com.rustdesk.RustDesk
        im.riot.Riot
        com.system76.Popsicle)

    log INFO "Installing essential Flatpak applications..."
    for app in "${essential_flatpaks[@]}"; do
        if ! sudo -u "$ACTUAL_USER" flatpak install -y "$app" &>>"$LOG_FILE"; then
            log WARN "Failed to install Flatpak: $app"
        fi
    done

    # Enable services
    systemctl enable --now bluetooth power-profiles-daemon

    log INFO "Essential applications installed"
}

install_development_tools() {
    if [[ ! " ${USER_STEPS[*]} " =~ coding ]]; then
        log INFO "Skipping development tools"
        return 0
    fi

    log INFO "Installing development tools..."

    # Install Neovim and dependencies
    install_packages neovim ripgrep fd

    # Install Rust
    install_rust

    # Install rclone
    install_rclone

    log INFO "Development tools installed"
}

install_rust() {
    log INFO "Installing Rust..."

    if ! sudo -u "$ACTUAL_USER" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' &>>"$LOG_FILE"; then
        log ERROR "Failed to install Rust"
        return 1
    fi

    log INFO "Rust installed successfully"
}

install_rclone() {
    log INFO "Installing rclone..."

    if ! curl https://rclone.org/install.sh | bash &>>"$LOG_FILE"; then
        log ERROR "Failed to install rclone"
        return 1
    fi

    log INFO "rclone installed successfully"
}

install_multimedia_apps() {
    if [[ ! " ${USER_STEPS[*]} " =~ media ]]; then
        log INFO "Skipping multimedia applications"
        return 0
    fi

    log INFO "Installing multimedia applications..."

    # Multimedia packages
    local multimedia_packages=(
        ffmpeg yt-dlp vlc mpv ffmpegthumbs
        gstreamer gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
        mediainfo flac lame libmpeg2 wavpack x264 x265
        noto-fonts noto-fonts-cjk noto-fonts-emoji
        ttf-jetbrains-mono-nerd ttf-liberation ttf-dejavu ttf-roboto
        intel-media-driver libva-intel-driver libva-mesa-driver mesa-vdpau
        vulkan-radeon lib32-vulkan-radeon vlc-plugins-all)

    install_packages "${multimedia_packages[@]}"

    # Multimedia Flatpaks
    local multimedia_flatpaks=(
        dev.vencord.Vesktop
        com.spotify.Client
        com.mastermindzh.tidal-hifi
        com.github.iwalton3.jellyfin-media-player
        org.kde.gwenview
        com.obsproject.Studio
        org.nickvision.tubeconverter
        io.github.dimtpap.coppwr
        org.nickvision.cavalier
        com.github.unrud.VideoDownloader)

    for app in "${multimedia_flatpaks[@]}"; do
        if ! sudo -u "$ACTUAL_USER" flatpak install -y "$app" &>>"$LOG_FILE"; then
            log WARN "Failed to install Flatpak: $app"
        fi
    done

    log INFO "Multimedia applications installed"
}

install_gaming_apps() {
    if [[ ! " ${USER_STEPS[*]} " =~ gaming ]]; then
        log INFO "Skipping gaming applications"
        return 0
    fi

    log INFO "Installing gaming applications..."

    # Gaming packages
    local gaming_packages=(
        steam lib32-mangohud mangohud gamemode lib32-gamemode
        rocm-core rocm-hip-libraries rocm-hip-runtime rocm-opencl-runtime)

    install_packages "${gaming_packages[@]}"

    # Gaming Flatpaks
    local gaming_flatpaks=(
        net.lutris.Lutris
        com.heroicgameslauncher.hgl
        org.yuzu_emu.yuzu
        net.davidotek.pupgui2)

    for app in "${gaming_flatpaks[@]}"; do
        if ! sudo -u "$ACTUAL_USER" flatpak install -y "$app" &>>"$LOG_FILE"; then
            log WARN "Failed to install Flatpak: $app"
        fi
    done

    log INFO "Gaming applications installed"
}

# Download and install MunchieHUD MangoHud configs
install_munchiehud_configs() {
    # --- Use ACTUAL_HOME and ACTUAL_USER instead of hardcoded values
    local config_dir="${ACTUAL_HOME}/.config/MangoHud"
    local files=(
        "MangoHud.conf"
        "Presets.conf")
    local urls=(
        "https://raw.githubusercontent.com/linuxmunchies/MunchieHUD/main/MangoHud.conf"
        "https://raw.githubusercontent.com/linuxmunchies/MunchieHUD/main/Presets.conf")
    local total="${#files[@]}"
    local i

    log INFO "Ensuring MangoHud config directory exists at $config_dir"
    # --- Create directory as the correct user
    sudo -u "$ACTUAL_USER" mkdir -p "$config_dir" || error_exit "Failed to create $config_dir"

    for ((i = 0; i < total; i++)); do
        local dest="$config_dir/${files[$i]}"
        local url="${urls[$i]}"
        show_progress $((i + 1)) "$total" "Downloading ${files[$i]}"

        # --- Download as the correct user
        if sudo -u "$ACTUAL_USER" curl -fsSL "$url" -o "$dest"; then
            log INFO "Downloaded ${files[$i]} successfully"
        else
            log ERROR "Failed to download ${files[$i]} from $url"
            return 1
        fi
    done

    log INFO "All MangoHud configs installed to $config_dir"
    return 0
}

install_browsers() {
    if [[ ! " ${USER_STEPS[*]} " =~ browsers ]]; then
        log INFO "Skipping browser applications"
        return 0
    fi

    log INFO "Installing browsers..."

    local browser_flatpaks=(
        io.gitlab.librewolf-community)

    for app in "${browser_flatpaks[@]}"; do
        if ! sudo -u "$ACTUAL_USER" flatpak install -y "$app" &>>"$LOG_FILE"; then
            log WARN "Failed to install Flatpak: $app"
        fi
    done

    log INFO "Browsers installed"
}

install_office_apps() {
    if [[ ! " ${USER_STEPS[*]} " =~ office ]]; then
        log INFO "Skipping office applications"
        return 0
    fi

    log INFO "Installing office applications..."

    install_packages kate

    local office_flatpaks=(
        org.gimp.GIMP
        org.onlyoffice.desktopeditors
        md.obsidian.Obsidian
        net.ankiweb.Anki)

    for app in "${office_flatpaks[@]}"; do
        if ! sudo -u "$ACTUAL_USER" flatpak install -y "$app" &>>"$LOG_FILE"; then
            log WARN "Failed to install Flatpak: $app"
        fi
    done

    log INFO "Office applications installed"
}

# ===================================================================
# SHELL AND DOTFILES CONFIGURATION
# ===================================================================

setup_zsh() {
    log INFO "Setting up Zsh shell..."

    # Install Zsh if not present
    if ! command -v zsh &>/dev/null; then
        install_packages zsh
    fi

    # Change default shell
    if [[ $(getent passwd "$ACTUAL_USER" | cut -d: -f7) != "$(which zsh)" ]]; then
        chsh -s "$(which zsh)" "$ACTUAL_USER"
        log INFO "Changed default shell to Zsh for $ACTUAL_USER"
    fi

    log INFO "Zsh setup completed. Dotfiles will be handled separately."
}

setup_dotfiles() {
    log INFO "Setting up dotfiles from $DOTFILES_REPO..."

    # Ensure git is installed
    if ! command -v git &>/dev/null; then
        install_packages git
    fi

    # Clone the dotfiles repository as the user
    if [[ -d "$DOTFILES_DIR" ]]; then
        log INFO "Dotfiles directory already exists. Pulling latest changes."
        sudo -u "$ACTUAL_USER" git -C "$DOTFILES_DIR" pull
    else
        log INFO "Cloning dotfiles repository..."
        sudo -u "$ACTUAL_USER" git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    # Find files in the root of the repo to symlink
    local dotfiles_to_link
    dotfiles_to_link=$(find "$DOTFILES_DIR" -maxdepth 1 -type f -printf "%f\n")

    for file in $dotfiles_to_link; do
        local source_file="$DOTFILES_DIR/$file"
        local dest_file="$ACTUAL_HOME/$file"

        # Back up existing file if it's a real file or a symlink
        if [[ -e "$dest_file" || -L "$dest_file" ]]; then
            local backup_file="$dest_file.backup.$(date +%Y%m%d%H%M%S)"
            log INFO "Backing up existing $dest_file to $backup_file"
            sudo -u "$ACTUAL_USER" mv "$dest_file" "$backup_file"
        fi

        # Create the symlink
        log INFO "Creating symlink for $file"
        sudo -u "$ACTUAL_USER" ln -s "$source_file" "$dest_file"
    done

    log INFO "Dotfiles setup completed."
}

# ===================================================================
# SPECIALIZED SETUPS
# ===================================================================

setup_virtualization() {
    log INFO "Setting up virtualization..."

    local virt_packages=(
        qemu-full samba libvirt virt-manager dnsmasq
        wine wine-mono wine-gecko winetricks)

    install_packages "${virt_packages[@]}"

    # Enable services
    systemctl enable --now libvirtd

    # Add user to libvirt group
    usermod -aG libvirt "$ACTUAL_USER"

    log INFO "Virtualization setup completed"
}

fix_apple_keyboard() {
    local fnmode_path="/sys/module/hid_apple/parameters/fnmode"

    if [ ! -f "$fnmode_path" ]; then
        log INFO "Apple keyboard fix not applicable (hid_apple module not detected)."
        return 0
    fi

    log INFO "Applying Apple keyboard function key fix..."

    # Create the modprobe configuration file to set the option on boot
    local conf_file="/etc/modprobe.d/hid_apple.conf"
    log INFO "Creating configuration file: $conf_file"
    if echo "options hid_apple fnmode=2" > "$conf_file"; then
        log INFO "Configuration file for hid_apple created."
    else
        log ERROR "Failed to create hid_apple configuration file."
        return 1
    fi

    # Rebuild the initramfs using mkinitcpio for Arch Linux
    log INFO "Rebuilding the initramfs with 'mkinitcpio' for keyboard fix..."
    if mkinitcpio -P &>>"$LOG_FILE"; then
        log INFO "Initramfs rebuilt successfully for keyboard fix."
    else
        log ERROR "Failed to rebuild initramfs for keyboard fix."
        return 1
    fi

    log INFO "Apple keyboard fix applied. A reboot is required."
}

install_mullvad_vpn() {
    log INFO "Installing Mullvad VPN..."

    if ! sudo -u "$ACTUAL_USER" yay -S --noconfirm mullvad-vpn-bin &>>"$LOG_FILE"; then
        log ERROR "Failed to install Mullvad VPN"
        return 1
    fi

    log INFO "Mullvad VPN installed successfully"
}

download_feishin() {
    log INFO "Installing Feishin AppImage..."

    local downloads_dir="$ACTUAL_HOME/Downloads"
    mkdir -p "$downloads_dir"

    # Get latest release info
    local latest_url
    latest_url=$(curl -s -L -I -o /dev/null -w '%{url_effective}' https://github.com/jeffvli/feishin/releases/latest)

    local version
    version=$(echo "$latest_url" | grep -o 'v[0-9.]*$' | sed 's/v//')

    if [[ -z "$version" ]]; then
        log ERROR "Could not determine latest Feishin version"
        return 1
    fi

    local download_url="https://github.com/jeffvli/feishin/releases/download/v${version}/Feishin-${version}-linux-x86_64.AppImage"
    local output_file="$downloads_dir/Feishin-${version}-linux-x86_64.AppImage"

    if sudo -u "$ACTUAL_USER" curl -L -o "$output_file" "$download_url"; then
        chmod +x "$output_file"
        log INFO "Feishin AppImage downloaded to $output_file"
    else
        log ERROR "Failed to download Feishin"
        return 1
    fi
}

fix_i2c_permissions() {
    log INFO "Fixing I2C permissions for ddcutil..."

    # Create i2c group
    if ! getent group i2c &>/dev/null; then
        groupadd --system i2c
    fi

    # Add user to i2c group
    usermod -aG i2c "$ACTUAL_USER"

    # Create udev rule
    local udev_rule="/etc/udev/rules.d/45-ddcutil-i2c.rules"
    echo 'SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"' >"$udev_rule"

    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger

    log INFO "I2C permissions configured"
}

create_directory_structure() {
    log INFO "Creating user directory structure..."

    for dir in "${DIRECTORIES_TO_CREATE[@]}"; do
        if sudo -u "$ACTUAL_USER" mkdir -p "$dir"; then
            log INFO "Created directory: $dir"
        else
            log WARN "Failed to create directory: $dir"
        fi
    done

    # Ensure proper ownership
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/ProtonDrive" "$ACTUAL_HOME/Development" 2>/dev/null || true

    log INFO "Directory structure created"
}

# ===================================================================
# SYSTEM INTEGRITY & BOOTLOADER
# ===================================================================

create_system_snapshot() {
    log INFO "Creating system snapshot with Timeshift..."

    # Install Timeshift if not present
    if ! command -v timeshift &>/dev/null; then
        log INFO "Timeshift not found, installing..."
        if ! install_packages timeshift; then
            log ERROR "Failed to install Timeshift. Cannot create snapshot."
            return 1 # This is a failure in the function, but we'll treat it as non-fatal in main
        fi
    fi

    # Create the snapshot
    if timeshift --create --comments "Vimmarch: Pre-setup snapshot" --yes &>>"$LOG_FILE"; then
        log INFO "Timeshift snapshot created successfully."
    else
        log WARN "Failed to create Timeshift snapshot. This could be because Timeshift is not configured."
        log WARN "You can configure it by running 'sudo timeshift-gtk'. Continuing without snapshot."
    fi
}

update_bootloader() {
    log INFO "Updating bootloader configuration..."

    if command -v grub-mkconfig &>/dev/null && [[ -d /boot/grub ]]; then
        log INFO "GRUB bootloader detected. Updating configuration..."
        if grub-mkconfig -o /boot/grub/grub.cfg &>>"$LOG_FILE"; then
            log INFO "GRUB configuration updated successfully."
        else
            log ERROR "Failed to update GRUB configuration."
            return 1
        fi
    elif command -v bootctl &>/dev/null && [[ -d /boot/loader ]]; then
        log INFO "systemd-boot bootloader detected. Updating..."
        if bootctl update &>>"$LOG_FILE"; then
            log INFO "systemd-boot updated successfully."
        else
            log ERROR "Failed to update systemd-boot."
            return 1
        fi
    else
        log WARN "No supported bootloader (GRUB or systemd-boot) detected. Skipping update."
    fi
    return 0
}

# ===================================================================
# CLEANUP AND OPTIMIZATION
# ===================================================================

system_cleanup() {
    log INFO "Performing system cleanup..."

    # Clean package cache (keep last 3 versions)
    paccache -rk3 &>>"$LOG_FILE" || pacman -Sc --noconfirm &>>"$LOG_FILE"

    # Remove orphaned packages
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null || true)
    if [[ -n "$orphans" ]]; then
        log INFO "Removing orphaned packages: $orphans"
        pacman -Rns --noconfirm $orphans &>>"$LOG_FILE"
    fi

    # Clean Flatpak
    sudo -u "$ACTUAL_USER" flatpak uninstall --unused -y &>>"$LOG_FILE"

    # Clean temporary files
    find /tmp -type f -atime +7 -delete 2>/dev/null || true

    # Clean journal logs (keep last 30 days)
    journalctl --vacuum-time=30d &>>"$LOG_FILE"

    log INFO "System cleanup completed"
}

# ===================================================================
# REPORTING AND SUMMARY
# ===================================================================

generate_system_report() {
    local report_file="$ACTUAL_HOME/Desktop/system_setup_report.txt"

    log INFO "Generating system report..."

    cat >"$report_file" <<EOF
# Arch Linux Setup Report
Generated: $(date)
Script Version: $SCRIPT_VERSION
Setup Duration: $((SECONDS / 60)) minutes

## System Information
$(hostnamectl)

## Hardware Information
$(lscpu | head -20)

## Memory Information
$(free -h)

## Storage Information
$(lsblk)

## Graphics Information
$(lspci | grep -i vga)

## Network Information
$(ip addr show | grep -E '^[0-9]+:|inet ')

## Installed Packages (last 50)
$(pacman -Q | tail -50)

## Active Services
$(systemctl list-units --type=service --state=active --no-pager | head -20)

## Mount Points
$(mount | grep -E '^/' | column -t)

## Setup Log Summary
Errors: $(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
Warnings: $(grep -c "WARN" "$LOG_FILE" 2>/dev/null || echo "0")

EOF

    chown "$ACTUAL_USER:$ACTUAL_USER" "$report_file"

    log INFO "System report generated: $report_file"
}

display_summary() {
    log INFO "Setup completed successfully!"

    C_GREEN='\033[1;32m'
    C_YELLOW='\033[1;33m'
    C_CYAN='\033[1;36m'
    C_BOLD='\033[1m'
    C_NC='\033[0m'

    echo ""
    echo -e "${C_GREEN}╔════════════════════════════════════════════════════════════╗${C_NC}"
    echo -e "${C_GREEN}║                    SETUP COMPLETE                          ║${C_NC}"
    echo -e "${C_GREEN}╚════════════════════════════════════════════════════════════╝${C_NC}"
    echo ""
    echo -e "${C_CYAN}📊 Setup Statistics:${C_NC}"
    echo -e "   • ${C_BOLD}Duration:${C_NC} $((SECONDS / 60)) minutes"
    echo -e "   • ${C_BOLD}Errors:${C_NC} $(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo -e "   • ${C_BOLD}Warnings:${C_NC} $(grep -c "WARN" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo ""
    echo -e "${C_CYAN}📁 Important Files:${C_NC}"
    echo -e "   • ${C_BOLD}Log file:${C_NC} $LOG_FILE"
    echo -e "   • ${C_BOLD}System report:${C_NC} $ACTUAL_HOME/Desktop/system_setup_report.txt"
    echo -e "   • ${C_BOLD}Backups:${C_NC} $BACKUP_DIR"
    echo ""
    echo -e "${C_YELLOW}🔄 Post-Setup Actions Required:${C_NC}"
    echo -e "   • Reboot to activate all changes"
    echo -e "   • Configure Timeshift snapshots via GUI"
    echo -e "   • Set up Mullvad VPN credentials"
    echo ""
    echo -e "${C_CYAN}💡 Tips:${C_NC}"
    echo -e "   • Check mounted drives: ${C_BOLD}df -h${C_NC}"
    echo -e "   • Update firmware: ${C_BOLD}fwupdmgr update${C_NC}"
    echo -e "   • View system info: ${C_BOLD}fastfetch${C_NC}"
    echo ""

    if command -v fastfetch &>/dev/null; then
        echo "Current System Info:"
        fastfetch
    fi
}

# ===================================================================
# USER INTERACTION & ARGUMENT PARSING
# ===================================================================

# --- Global user choices ---
USER_CPU=""
USER_GPU=""
USER_LAPTOP=""
USER_STEPS=()
USER_GAMEDRIVE_UUID=""
NON_INTERACTIVE=false
CONFIG_FILE=""

# --- TUI for user choices ---
get_user_choices() {
    # Check for whiptail, fallback to read if not present
    use_whiptail=false
    if command -v whiptail &>/dev/null; then
        use_whiptail=true
    fi

    # CPU selection
    if $use_whiptail; then
        USER_CPU=$(whiptail --title "CPU Selection" --menu "Select your CPU type:" 15 60 4 \
            "amd" "AMD Ryzen/EPYC" \
            "intel" "Intel Core/Xeon" \
            "other" "Other/Unknown" 3>&1 1>&2 2>&3)
    else
        echo "Select your CPU type:"
        select cpu in "amd" "intel" "other"; do
            USER_CPU="$cpu"
            break
        done
    fi

    # GPU selection
    if $use_whiptail; then
        USER_GPU=$(whiptail --title "GPU Selection" --menu "Select your GPU type:" 15 60 4 \
            "amd" "AMD Radeon" \
            "intel" "Intel Graphics" \
            "nvidia" "NVIDIA" \
            "other" "Other/Unknown" 3>&1 1>&2 2>&3)
    else
        echo "Select your GPU type:"
        select gpu in "amd" "intel" "nvidia" "other"; do
            USER_GPU="$gpu"
            break
        done
    fi

    # Laptop selection
    if $use_whiptail; then
        if whiptail --title "Laptop" --yesno "Is this device a laptop?" 10 60; then
            USER_LAPTOP="yes"
        else
            USER_LAPTOP="no"
        fi
    else
        read -rp "Is this device a laptop? (y/n): " ans
        [[ "${ans,,}" =~ ^y ]] && USER_LAPTOP="yes" || USER_LAPTOP="no"
    fi

    # Step selection (multi-choice)
    if $use_whiptail; then
        local step_choices
        step_choices=$(whiptail --title "Setup Steps" --checklist "Select steps to run (use space to select):" 20 78 12 \
            "directory_structure" "Create user directories" ON \
            "dotfiles" "Setup dotfiles from Git" ON \
            "firewall" "Setup UFW firewall" ON \
            "gamedrive" "Game drive setup" ON \
            "essentials" "Essential apps" ON \
            "coding" "Development tools" ON \
            "media" "Multimedia apps" ON \
            "gaming" "Gaming apps" ON \
            "browsers" "Browsers" ON \
            "office" "Office apps" ON \
            "virtualization" "Virtualization" OFF 3>&1 1>&2 2>&3)
        USER_STEPS=($step_choices)
    else
        echo "Select steps to run (comma separated):"
        echo "Options: directory_structure, dotfiles, firewall, gamedrive, essentials, coding, media, gaming, browsers, office, virtualization"
        read -rp "Steps: " steps
        IFS=',' read -ra USER_STEPS <<<"$steps"
    fi

    # Gamedrive selection (if enabled)
    if [[ " ${USER_STEPS[*]} " =~ gamedrive ]]; then
        # List available BTRFS drives by UUID
        local drives
        drives=($( blkid -t TYPE=btrfs -o value -s UUID))
        if [[ ${#drives[@]} -eq 0 ]]; then
            log WARN "No BTRFS drives detected for gamedrive setup"
            USER_GAMEDRIVE_UUID=""
        elif [[ ${#drives[@]} -eq 1 ]]; then
            USER_GAMEDRIVE_UUID="${drives[0]}"
        else
            if $use_whiptail; then
                local menu_args=()
                for uuid in "${drives[@]}"; do
                    menu_args+=("$uuid" "$(blkid -U $uuid)")
                done
                USER_GAMEDRIVE_UUID=$(whiptail --title "Game Drive Selection" --menu "Select the game drive UUID:" 20 70 10 "${menu_args[@]}" 3>&1 1>&2 2>&3)
            else
                echo "Select the game drive UUID:"
                select uuid in "${drives[@]}"; do
                    USER_GAMEDRIVE_UUID="$uuid"
                    break
                done
            fi
        fi
    fi
}

# --- Argument parsing and config loading ---
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            display_help
            exit 0
            ;;
        --config)
            if [[ -n "$2" ]]; then
                CONFIG_FILE="$2"
                NON_INTERACTIVE=true
                shift
            else
                error_exit "ERROR: --config requires a file path."
            fi
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
        esac
        shift
    done
}

load_config_file() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log INFO "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        error_exit "Configuration file not found: $CONFIG_FILE"
    fi
}

display_help() {
    cat <<EOF
Arch Linux Setup Script v$SCRIPT_VERSION

Usage: sudo $0 [options]

Options:
 -h, --help         Show this help message
 --config FILE      Use a configuration file to run non-interactively.

Features:
 • Automated system optimization
 • Game drive setup
 • Dotfiles management from Git
 • UFW firewall setup
 • GPU driver optimization
 • Development environment setup
 • Gaming platform installation
 • Comprehensive error handling
 • Detailed logging and reporting

Example config file (e.g., setup.conf):
------------------------------------------
USER_CPU="amd"
USER_GPU="amd"
USER_LAPTOP="no"
USER_STEPS=("directory_structure" "dotfiles" "firewall" "essentials" "coding")
USER_GAMEDRIVE_UUID="your-btrfs-drive-uuid-here"
------------------------------------------

This script must be run as root (with sudo).
EOF
}

# ===================================================================
# MAIN EXECUTION FLOW
# ===================================================================

main() {
    local start_time=$SECONDS

    # --- Determine run mode: Interactive or Non-Interactive ---
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        load_config_file
    else
        display_welcome_banner
        get_user_choices
    fi

    # Initialize
    validate_system

    log INFO "Starting Arch Linux setup script v$SCRIPT_VERSION"
    log INFO "User: $ACTUAL_USER, Home: $ACTUAL_HOME"

    # Create a safety snapshot before we begin
    create_system_snapshot || log WARN "Could not create system snapshot. Continuing with setup."

    # System preparation phase
    log INFO "=== SYSTEM PREPARATION PHASE ==="
    optimize_mirrors || log WARN "Mirror optimization failed"
    system_upgrade
    configure_pacman
    setup_timezone

    # Hardware and drivers phase
    log INFO "=== HARDWARE OPTIMIZATION PHASE ==="
    install_cpu_specific_packages
    install_gpu_specific_packages
    install_laptop_packages
    setup_gpu_optimization
    fix_apple_keyboard
    update_bootloader || log ERROR "Failed to update bootloader. This may cause issues on reboot."

    # Core services phase
    log INFO "=== CORE SERVICES PHASE ==="
    setup_aur_helper
    setup_flatpak
    if [[ " ${USER_STEPS[*]} " =~ directory_structure ]]; then
        create_directory_structure
    fi

    # Storage setup phase
    log INFO "=== STORAGE SETUP PHASE ==="
    if [[ " ${USER_STEPS[*]} " =~ gamedrive ]]; then
        if [[ -n "$USER_GAMEDRIVE_UUID" ]]; then
            GAME_DRIVE_UUID="$USER_GAMEDRIVE_UUID"
            setup_game_drive || log WARN "Game drive setup failed or skipped"
        else
            log WARN "No game drive UUID selected, skipping game drive setup"
        fi
    fi

    # Application installation phase
    log INFO "=== APPLICATION INSTALLATION PHASE ==="
    if [[ " ${USER_STEPS[*]} " =~ essentials ]]; then
        install_essential_apps
    fi
    if [[ " ${USER_STEPS[*]} " =~ coding ]]; then
        install_development_tools
    fi
    if [[ " ${USER_STEPS[*]} " =~ media ]]; then
        install_multimedia_apps
    fi
    if [[ " ${USER_STEPS[*]} " =~ gaming ]]; then
        install_gaming_apps
        install_munchiehud_configs
    fi
    if [[ " ${USER_STEPS[*]} " =~ browsers ]]; then
        install_browsers
    fi
    if [[ " ${USER_STEPS[*]} " =~ office ]]; then
        install_office_apps
    fi
    if [[ " ${USER_STEPS[*]} " =~ virtualization ]]; then
        setup_virtualization
    fi
    install_mullvad_vpn || log WARN "Mullvad VPN installation failed"
    download_feishin || log WARN "Feishin download failed"

    # System configuration phase
    log INFO "=== SYSTEM CONFIGURATION PHASE ==="
    setup_zsh
    if [[ " ${USER_STEPS[*]} " =~ dotfiles ]]; then
        setup_dotfiles
    fi
    if [[ " ${USER_STEPS[*]} " =~ firewall ]]; then
        setup_firewall
    fi
    fix_i2c_permissions

    # Optimization phase
    log INFO "=== CLEANUP PHASE ==="
    system_cleanup

    # Finalization phase
    log INFO "=== FINALIZATION PHASE ==="
    generate_system_report
    display_summary

    log INFO "Setup script completed in $((SECONDS - start_time)) seconds"

    # Prompt for reboot
    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        echo ""
        if confirm_with_timeout "Reboot now to activate all changes?" 30 "y"; then
            log INFO "Rebooting system..."
            reboot
        else
            log INFO "Remember to reboot later to activate all changes"
        fi
    else
        log INFO "Non-interactive mode: Skipping reboot prompt. Please reboot manually."
    fi
}

# ===================================================================
# SCRIPT ENTRY POINT
# ===================================================================

# Trap signals for cleanup
trap 'log ERROR "Script interrupted"; exit 130' INT TERM

# Parse command-line arguments before anything else
parse_arguments "$@"

# Execute main function
main
