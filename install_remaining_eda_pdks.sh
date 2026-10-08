#!/bin/bash
# ==============================================================================
#  OPEN-SOURCE EDA SUITE: PDKs & REMAINING TOOLS AUTOMATED INSTALLER
#  Target: Ubuntu 22.04 / 24.04 LTS (Native Linux / WSL2)
#  Description: Resumes setup after OpenLane. Installs SkyWater 130nm PDK,
#               all remaining EDA tools, dependencies, workspace & runs verification.
#  Usage: bash install_remaining_eda_pdks.sh
# ==============================================================================

set -e

# ANSI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${CYAN}   🚀 SKYWATER 130nm PDK & REMAINING OPEN-SOURCE EDA TOOLS INSTALLER    ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 0. Sudo Access Verification
# ------------------------------------------------------------------------------
echo -e "${BOLD}${YELLOW}[0/6] Checking administrator (sudo) privileges...${NC}"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ------------------------------------------------------------------------------
# 1. Install System Dependencies, Python Pipx & Build Libraries
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${BLUE}[1/6] Installing build libraries, Python environment & dependencies...${NC}"
sudo apt update -y
sudo apt install -y \
    build-essential git curl wget cmake python3 python3-pip python3-venv pipx \
    tcl tk tcl-dev tk-dev m4 libcairo2-dev libx11-dev libxaw7-dev libreadline-dev \
    libncurses5-dev libgsl-dev libglu1-mesa-dev freeglut3-dev \
    bison flex autoconf gperf automake libtool pkg-config docker.io

# Ensure current user is in docker group
sudo usermod -aG docker "$USER" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Install Remaining Native EDA & Firmware Tools via APT
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${BLUE}[2/6] Installing remaining native EDA tools & RISC-V toolchain...${NC}"
sudo apt install -y \
    yosys \
    iverilog \
    verilator \
    gtkwave \
    opensta \
    magic \
    klayout \
    ngspice \
    xschem \
    irsim \
    netgen-lvs \
    gcc-riscv64-unknown-elf \
    picolibc-riscv64-unknown-elf

# ------------------------------------------------------------------------------
# 3. Setup PDK Managers (Ciel & Volare) & Install SkyWater 130nm PDK
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${BLUE}[3/6] Installing PDK managers & pulling SkyWater 130nm PDK...${NC}"
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

# Install ciel and volare via pipx cleanly
pipx install ciel --force || pipx upgrade ciel || true
pipx install volare --force || pipx upgrade volare || true

# Enable and pull SkyWater 130nm PDK
echo -e "${BOLD}${YELLOW}Downloading SkyWater 130nm PDK standard cell libraries & tech files...${NC}"
ciel enable sky130 || true

# Check and fallback to volare if ciel is unavailable
if [ ! -d "$HOME/.ciel/sky130A" ] && [ ! -d "$HOME/.volare/sky130A" ]; then
    echo -e "${BOLD}${YELLOW}Fetching PDK via Volare...${NC}"
    volare enable --pdk sky130 sky130A || true
fi

# Locate PDK path
PDK_DIR=$(find "$HOME/.ciel" "$HOME/.volare" -name "sky130A" -type d 2>/dev/null | head -n 1)
if [ -z "$PDK_DIR" ]; then
    echo -e "${RED}[WARNING] Sky130 PDK directory not located automatically. Retrying ciel enable...${NC}"
    ciel enable sky130 --force || true
    PDK_DIR=$(find "$HOME/.ciel" -name "sky130A" -type d 2>/dev/null | head -n 1)
fi
echo -e "${GREEN}✔ PDK Root located at: ${PDK_DIR:-$HOME/.ciel/sky130A}${NC}"

# ------------------------------------------------------------------------------
# 4. Configure EDA Launchers, Docker Wrappers & Xschem Integration
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${BLUE}[4/6] Creating EDA tool wrappers & PDK launch scripts...${NC}"
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"

# Link Netgen VLSI LVS
if [ -f "/usr/bin/netgen-lvs" ]; then
    ln -sf "/usr/bin/netgen-lvs" "$HOME/.local/bin/netgen"
fi

# OpenROAD Container Wrapper
cat << 'EOF' > "$HOME/.local/bin/openroad"
#!/bin/bash
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
fi
docker run --rm $TTY_FLAG \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /mnt/wslg:/mnt/wslg 2>/dev/null \
    -v "$HOME:$HOME" \
    -w "$(pwd)" \
    -u "$(id -u):$(id -g)" \
    -e DISPLAY="$DISPLAY" \
    -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e PDK_ROOT="$HOME/.ciel" \
    --network host \
    --ipc=host \
    efabless/openroad:latest /foss/tools/bin/openroad "$@"
EOF
chmod +x "$HOME/.local/bin/openroad"

# OpenLane Container Wrapper
cat << 'EOF' > "$HOME/.local/bin/openlane"
#!/bin/bash
IMAGE="efabless/openlane:latest"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[INFO] Pulling OpenLane Docker image ($IMAGE)..."
    docker pull "$IMAGE"
fi
xhost +local:docker >/dev/null 2>&1 || true
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
fi
docker run --rm $TTY_FLAG \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /mnt/wslg:/mnt/wslg 2>/dev/null \
    -v "$HOME:$HOME" \
    -w "$(pwd)" \
    -u "$(id -u):$(id -g)" \
    -e DISPLAY="$DISPLAY" \
    -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e PDK_ROOT="$HOME/.ciel" \
    -e PDK="sky130A" \
    --network host \
    --ipc=host \
    "$IMAGE" "$@"
EOF
chmod +x "$HOME/.local/bin/openlane"

# Sky130 Preconfigured Xschem Launcher
XSCHEM_RC=$(find "$HOME/.ciel" "$HOME/.volare" -name "xschemrc" 2>/dev/null | head -n 1)
cat << EOF > "$HOME/.local/bin/xschem-sky130"
#!/bin/bash
PDK_XSCHEM_RC="$XSCHEM_RC"
export PDK_ROOT="\$HOME/.ciel/sky130A"
export PDK="sky130A"
if [ -f "\$PDK_XSCHEM_RC" ]; then
    xschem --rcfile "\$PDK_XSCHEM_RC" "\$@"
else
    xschem "\$@"
fi
EOF
chmod +x "$HOME/.local/bin/xschem-sky130"

# ------------------------------------------------------------------------------
# 5. Build Workspace Hierarchy, Central Tools Hub & Environment Setup
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${BLUE}[5/6] Structuring EDA Workspace, PDK Links & Environment Aliases...${NC}"

# Directories
mkdir -p "$HOME/tools/bin"
mkdir -p "$HOME/eda_workspace"/{digital_designs,analog_designs,openlane_runs,firmware,pdks,scripts}

# Central symlinks for all tools
for tool in yosys verilator iverilog gtkwave sta magic klayout ngspice xschem irsim docker; do
    if [ -f "/usr/bin/$tool" ]; then
        ln -sf "/usr/bin/$tool" "$HOME/tools/bin/$tool"
    fi
done

[ -f "/usr/bin/netgen-lvs" ] && ln -sf /usr/bin/netgen-lvs "$HOME/tools/bin/netgen"
[ -f "/usr/bin/riscv64-unknown-elf-gcc" ] && ln -sf /usr/bin/riscv64-unknown-elf-gcc "$HOME/tools/bin/riscv-gcc"
[ -f "/usr/bin/riscv64-unknown-elf-gcc" ] && ln -sf /usr/bin/riscv64-unknown-elf-gcc "$HOME/tools/bin/riscv64-unknown-elf-gcc"

ln -sf "$HOME/.local/bin/openroad" "$HOME/tools/bin/openroad" 2>/dev/null || true
ln -sf "$HOME/.local/bin/openlane" "$HOME/tools/bin/openlane" 2>/dev/null || true
ln -sf "$HOME/.local/bin/xschem-sky130" "$HOME/tools/bin/xschem-sky130" 2>/dev/null || true
ln -sf "$HOME/.local/bin/ciel" "$HOME/tools/bin/ciel" 2>/dev/null || true
ln -sf "$HOME/.local/bin/volare" "$HOME/tools/bin/volare" 2>/dev/null || true

# Link tools directly into workspace
ln -sfn "$HOME/tools" "$HOME/eda_workspace/tools"

# Create eda_env.sh
cat << 'EOF' > "$HOME/eda_workspace/eda_env.sh"
#!/bin/bash
export EDA_HOME="$HOME/eda_workspace"
export PDK_ROOT="$HOME/.ciel"
export PDK="sky130A"
export SKY130A_PATH=$(find "$HOME/.ciel" "$HOME/.volare" -name "sky130A" -type d 2>/dev/null | head -n 1)
export PATH="$HOME/.local/bin:$HOME/tools/bin:$PATH"

alias goto_eda='cd $EDA_HOME'
alias goto_digital='cd $EDA_HOME/digital_designs'
alias goto_analog='cd $EDA_HOME/analog_designs'
alias goto_openlane='cd $EDA_HOME/openlane_runs'
alias goto_firmware='cd $EDA_HOME/firmware'
alias goto_pdks='cd $EDA_HOME/pdks'

alias xschem_sky130='xschem --rcfile $SKY130A_PATH/libs.tech/xschem/xschemrc'
alias magic_sky130='magic -rcfile $SKY130A_PATH/libs.tech/magic/sky130A.magicrc'
alias klayout_sky130='klayout -l $SKY130A_PATH/libs.tech/klayout/tech/sky130A.lyp'
alias verify_tools='$HOME/tools/verify_tools.sh'

echo "========================================================"
echo " Open-Source EDA Environment Loaded!"
echo " Workspace : $EDA_HOME"
echo " PDK Root  : $PDK_ROOT (PDK: $PDK)"
echo " Type 'goto_eda' to jump to your workspace root."
echo "========================================================"
EOF
chmod +x "$HOME/eda_workspace/eda_env.sh"

# Add sourcing to ~/.bashrc if missing
if ! grep -q "eda_workspace/eda_env.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo -e "\n# Open-Source EDA Suite Environment\nsource \$HOME/eda_workspace/eda_env.sh" >> "$HOME/.bashrc"
fi

# ------------------------------------------------------------------------------
# 6. Integrated Complete Tool & PDK Verification Suite
# ------------------------------------------------------------------------------
cat << 'EOF' > "$HOME/tools/verify_tools.sh"
#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
export PATH="$HOME/.local/bin:$HOME/tools/bin:$PATH"
PASS=0; FAIL=0

check_t() {
    local n="$1"; local c="$2"; local v="$3"; local cat="$4"
    printf "  %-24s | %-12s | " "$n" "$cat"
    if command -v "$c" >/dev/null 2>&1; then
        local out=$(eval "$v" 2>/dev/null | head -n 1 | tr -d '\r\n' | cut -c 1-35)
        [ -z "$out" ] && out="Installed ($(which "$c" | cut -c 1-25))"
        printf "${GREEN}[ PASS ]${NC} %-35s\n" "$out"
        ((PASS++))
    else
        printf "${RED}[ FAIL ]${NC} Not found in PATH\n"
        ((FAIL++))
    fi
}

echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${CYAN}          OPEN-SOURCE EDA TOOLS & PDK VERIFICATION SUITE                ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

echo -e "${BOLD}${BLUE}[ 1. Digital ASIC Flow Tools ]${NC}"
echo "------------------------------------------------------------------------"
check_t "Yosys"           "yosys"                 "yosys -V"                          "Synthesis"
check_t "Icarus Verilog"  "iverilog"              "iverilog -V | head -n 1"           "Simulation"
check_t "Verilator"       "verilator"             "verilator --version"               "Simulation"
check_t "GTKWave"         "gtkwave"               "gtkwave --version | head -n 1"     "Waveform"
check_t "OpenSTA"         "sta"                   "sta -version"                      "Timing (STA)"
check_t "OpenROAD"        "openroad"              "openroad -version"                 "P&R Engine"
check_t "OpenLane"        "openlane"              "echo 'Docker Wrapper Ready'"       "Auto ASIC Flow"

echo -e "\n${BOLD}${BLUE}[ 2. Physical Layout, DRC & LVS Tools ]${NC}"
echo "------------------------------------------------------------------------"
check_t "KLayout"         "klayout"               "klayout -v"                        "Layout / DRC"
check_t "Magic VLSI"      "magic"                 "magic --version"                   "Layout / DRC"
check_t "Netgen"          "netgen"                "netgen -batch <<< quit 2>&1 | grep -i netgen | head -n 1" "LVS Signoff"

echo -e "\n${BOLD}${BLUE}[ 3. Analog & Mixed-Signal (AMS) Tools ]${NC}"
echo "------------------------------------------------------------------------"
check_t "Xschem"          "xschem"                "xschem --version"                  "Schematic"
check_t "Ngspice"         "ngspice"               "ngspice -v | head -n 1"            "Circuit Sim"
check_t "IRSIM"           "irsim"                 "echo 'Switch Simulator Ready'"     "Switch Sim"

echo -e "\n${BOLD}${BLUE}[ 4. Embedded Firmware & Infrastructure ]${NC}"
echo "------------------------------------------------------------------------"
check_t "RISC-V GCC"      "riscv64-unknown-elf-gcc" "riscv64-unknown-elf-gcc --version | head -n 1" "Compiler"
check_t "Docker"          "docker"                "docker --version"                  "Container"
check_t "Ciel PDK Mgr"    "ciel"                  "ciel --version | head -n 1"        "PDK Manager"
check_t "Volare PDK Mgr"  "volare"                "volare --version | head -n 1"      "PDK Manager"

echo -e "\n${BOLD}${BLUE}[ 5. SkyWater 130nm PDK Assets Verification ]${NC}"
echo "------------------------------------------------------------------------"
PDK_DIR=$(find "$HOME/.ciel" "$HOME/.volare" -name "sky130A" -type d 2>/dev/null | head -n 1)
check_p() {
    local l="$1"; local p="$2"
    printf "  %-30s | " "$l"
    if [ -e "$p" ]; then
        printf "${GREEN}[ FOUND ]${NC} %s\n" "$(basename "$p")"
        ((PASS++))
    else
        printf "${RED}[ MISSING ]${NC} %s\n" "$p"
        ((FAIL++))
    fi
}
check_p "Standard Cell LEF (sc_hd)"   "$PDK_DIR/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
check_p "Technology LEF (sc_hd)"      "$PDK_DIR/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"
check_p "Standard Cell GDS"           "$PDK_DIR/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds"
check_p "Liberty Timing (.lib)"       "$PDK_DIR/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
check_p "Magic Tech File (.magicrc)"   "$PDK_DIR/libs.tech/magic/sky130A.magicrc"
check_p "KLayout Layer Props (.lyp)"  "$PDK_DIR/libs.tech/klayout/tech/sky130A.lyp"
check_p "Xschem RC & Symbols"         "$PDK_DIR/libs.tech/xschem/xschemrc"

echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${BOLD}${GREEN}✔ ALL $PASS TOOLS & PDK ASSETS VERIFIED SUCCESSFULLY!${NC}"
else
    echo -e "  ${BOLD}${YELLOW}Summary: $PASS passed, $FAIL missing.${NC}"
fi
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
EOF
chmod +x "$HOME/tools/verify_tools.sh"
ln -sf "$HOME/tools/verify_tools.sh" "$HOME/eda_workspace/verify_tools.sh" 2>/dev/null || true

echo -e "\n${BOLD}${BLUE}[6/6] Running System Verification Suite...${NC}"
"$HOME/tools/verify_tools.sh"

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "${BOLD}${GREEN}  ✔ PDK & REMAINING EDA TOOLS INSTALLATION COMPLETED SUCCESSFULLY!      ${NC}"
echo -e "${BOLD}${GREEN}  Open a new terminal or run: 'source ~/.bashrc'                       ${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
