#!/usr/bin/env bash
# =============================================================================
#  Skillpulse — Secure GitOps on EKS
#  setup.sh  —  install all prerequisites
#  Supports: Ubuntu/Debian, Amazon Linux 2/2023, macOS
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*"; }
info()    { echo -e "${BLUE}[ℹ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $*"; }
error()   { echo -e "${RED}[✘]${NC} $*"; exit 1; }
section() {
  echo ""
  echo -e "${BOLD}${CYAN}=======================================${NC}"
  echo -e "${BOLD}${CYAN}  $*${NC}"
  echo -e "${BOLD}${CYAN}=======================================${NC}"
  echo ""
}

# =============================================================================
#  Detect OS
# =============================================================================
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
  elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu|debian)           OS="ubuntu" ;;
      amzn)                    OS="amazon" ;;
      *)                       OS="linux"  ;;
    esac
  else
    error "Unsupported OS. Install tools manually."
  fi
  log "Detected OS: $OS"
}

# =============================================================================
#  Helper — check if tool already installed
# =============================================================================
is_installed() { command -v "$1" &>/dev/null; }

# =============================================================================
#  Banner
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}=======================================${NC}"
echo -e "${BOLD}${CYAN}  Skillpulse  — Prerequisites Setup    ${NC}"
echo -e "${BOLD}${CYAN}=======================================${NC}"
echo ""

detect_os

# =============================================================================
#  STEP 0 — System dependencies (curl, wget, unzip, git, jq, python3)
# =============================================================================
section "STEP 0 · System dependencies"

case "$OS" in
  ubuntu)
    info "Updating apt and installing base packages..."
    sudo apt-get update -qq
    sudo apt-get install -y \
      curl wget unzip zip git gnupg \
      ca-certificates apt-transport-https \
      software-properties-common lsb-release \
      python3 jq
    log "System dependencies installed"
    ;;
  amazon|linux)
    info "Installing base packages via yum/dnf..."
    sudo yum install -y \
      curl wget unzip zip git gnupg2 \
      ca-certificates python3 jq 2>/dev/null || \
    sudo dnf install -y \
      curl wget unzip zip git gnupg2 \
      ca-certificates python3 jq 2>/dev/null
    log "System dependencies installed"
    ;;
  macos)
    if ! is_installed brew; then
      info "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    info "Installing base packages via Homebrew..."
    brew install curl wget unzip git python3 jq 2>/dev/null || true
    log "System dependencies installed"
    ;;
esac

# =============================================================================
#  STEP 1 — AWS CLI
# =============================================================================
section "STEP 1 · AWS CLI"

if is_installed aws; then
  AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
  log "AWS CLI already installed: v$AWS_VERSION"
else
  info "Installing AWS CLI v2..."
  case "$OS" in
    macos)
      curl -sSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
      sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
      ;;
    ubuntu)
      curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
      sudo /tmp/aws-install/aws/install
      rm -rf /tmp/awscliv2.zip /tmp/aws-install
      ;;
    amazon|linux)
      curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
      sudo /tmp/aws-install/aws/install
      rm -rf /tmp/awscliv2.zip /tmp/aws-install
      ;;
  esac
  log "AWS CLI installed: $(aws --version 2>&1)"
fi

# Configure AWS
echo ""
info "Checking AWS credentials..."
if aws sts get-caller-identity --output json &>/dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  USER=$(aws sts get-caller-identity --query Arn --output text)
  log "AWS already configured"
  echo -e "  Account : $ACCOUNT"
  echo -e "  Identity: $USER"
else
  warn "AWS credentials not configured."
  echo ""
  echo -e "  Run ${BOLD}aws configure${NC} and enter:"
  echo "    AWS Access Key ID"
  echo "    AWS Secret Access Key"
  echo "    Default region (e.g. us-west-2)"
  echo "    Default output format: json"
  echo ""
  read -rp "Configure AWS now? [yes/no]: " CONFIGURE_AWS
  if [[ "$CONFIGURE_AWS" == "yes" ]]; then
    aws configure
    aws sts get-caller-identity --output json \
      && log "AWS configured successfully" \
      || error "AWS configuration failed — check your credentials"
  else
    warn "Skipping AWS configuration — run 'aws configure' manually before deploying"
  fi
fi

# =============================================================================
#  STEP 2 — Terraform >= 1.5.7
# =============================================================================
section "STEP 2 · Terraform >= 1.5.7"

REQUIRED_TF="1.5.7"

install_terraform() {
  local VERSION
  # Get latest 1.x version
  VERSION=$(curl -sSL https://checkpoint-api.hashicorp.com/v1/check/terraform \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['current_version'])" \
    2>/dev/null || echo "1.9.5")

  info "Installing Terraform v$VERSION..."

  case "$OS" in
    macos)
      if is_installed brew; then
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
      else
        local ARCH
        ARCH=$(uname -m | sed 's/x86_64/amd64/;s/arm64/arm64/')
        curl -sSL "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_darwin_${ARCH}.zip" \
          -o /tmp/terraform.zip
        unzip -q /tmp/terraform.zip -d /tmp
        sudo mv /tmp/terraform /usr/local/bin/
        rm /tmp/terraform.zip
      fi
      ;;
    ubuntu)
      sudo apt-get update -qq
      sudo apt-get install -y gnupg software-properties-common
      wget -qO- https://apt.releases.hashicorp.com/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
      sudo apt-get update -qq
      sudo apt-get install -y terraform
      ;;
    amazon|linux)
      local ARCH
      ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
      curl -sSL "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip" \
        -o /tmp/terraform.zip
      unzip -q /tmp/terraform.zip -d /tmp
      sudo mv /tmp/terraform /usr/local/bin/
      rm /tmp/terraform.zip
      ;;
  esac
}

version_gte() {
  # Returns 0 if $1 >= $2
  printf '%s\n%s\n' "$2" "$1" | sort -C -V
}

if is_installed terraform; then
  TF_VERSION=$(terraform version -json | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null \
    || terraform version | head -1 | grep -oP '\d+\.\d+\.\d+')

  if version_gte "$TF_VERSION" "$REQUIRED_TF"; then
    log "Terraform already installed: v$TF_VERSION (>= $REQUIRED_TF required)"
  else
    warn "Terraform v$TF_VERSION is below required v$REQUIRED_TF — upgrading..."
    install_terraform
    log "Terraform upgraded: $(terraform version | head -1)"
  fi
else
  install_terraform
  log "Terraform installed: $(terraform version | head -1)"
fi

# =============================================================================
#  STEP 3 — kubectl
# =============================================================================
section "STEP 3 · kubectl"

if is_installed kubectl; then
  KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['clientVersion']['gitVersion'])" \
    2>/dev/null || kubectl version --client --short 2>/dev/null | head -1)
  log "kubectl already installed: $KUBECTL_VERSION"
else
  info "Installing kubectl..."
  case "$OS" in
    macos)
      if is_installed brew; then
        brew install kubectl
      else
        KUBECTL_VER=$(curl -sSL https://dl.k8s.io/release/stable.txt)
        curl -sSLO "https://dl.k8s.io/release/$KUBECTL_VER/bin/darwin/amd64/kubectl"
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/
      fi
      ;;
    ubuntu)
      # Remove any corrupted repo file first
      sudo rm -f /etc/apt/sources.list.d/kubernetes.list
      
      # Create the keyring directory if it doesn't exist
      sudo mkdir -p /etc/apt/keyrings
      
      # Download and add the GPG key
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
        sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      
      # Add the repository (all on one line to avoid formatting issues)
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
        sudo tee /etc/apt/sources.list.d/kubernetes.list
      
      sudo apt-get update -qq
      sudo apt-get install -y kubectl
      ;;
  esac
  log "kubectl installed: $(kubectl version --client --short 2>/dev/null | head -1)"
fi

# =============================================================================
#  STEP 4 — Helm 3
# =============================================================================
section "STEP 4 · Helm 3"

if is_installed helm; then
  HELM_VERSION=$(helm version --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+')
  log "Helm already installed: $HELM_VERSION"
else
  info "Installing Helm 3..."
  case "$OS" in
    macos)
      if is_installed brew; then
        brew install helm
      else
        curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      fi
      ;;
    ubuntu|amazon|linux)
      curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      ;;
  esac
  log "Helm installed: $(helm version --short)"
fi

# =============================================================================
#  STEP 5 — Docker
# =============================================================================
section "STEP 5 · Docker"

if is_installed docker; then
  DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
  log "Docker already installed: v$DOCKER_VERSION"
  # Check daemon is running
  if docker info &>/dev/null 2>&1; then
    log "Docker daemon is running"
  else
    warn "Docker installed but daemon not running"
    case "$OS" in
      macos)  warn "Start Docker Desktop manually" ;;
      ubuntu) sudo systemctl start docker && sudo systemctl enable docker \
                && log "Docker daemon started" ;;
      amazon) sudo systemctl start docker && sudo systemctl enable docker \
                && log "Docker daemon started" ;;
    esac
  fi
else
  info "Installing Docker..."
  case "$OS" in
    macos)
      warn "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
      warn "Skipping automatic install on macOS"
      ;;
    ubuntu)
      sudo apt-get update -qq
      sudo apt-get install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update -qq
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io
      sudo systemctl start docker
      sudo systemctl enable docker
      # Add current user to docker group
      sudo usermod -aG docker "$USER"
      warn "Logged out and back in (or run 'newgrp docker') to use Docker without sudo"
      ;;
    amazon|linux)
      sudo yum install -y docker 2>/dev/null || \
        sudo dnf install -y docker 2>/dev/null
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker "$USER"
      warn "Run 'newgrp docker' to use Docker without sudo"
      ;;
  esac
  is_installed docker && log "Docker installed: $(docker --version)" || \
    warn "Docker installation may require manual steps"
fi

# =============================================================================
#  Final Summary
# =============================================================================
section "Installation Summary"

check_tool() {
  local NAME="$1"
  local CMD="$2"
  if is_installed "$CMD"; then
    echo -e "  ${GREEN}✔${NC}  $NAME"
  else
    echo -e "  ${RED}✘${NC}  $NAME  ← not found"
  fi
}

check_tool "AWS CLI   " aws
check_tool "Terraform " terraform
check_tool "kubectl   " kubectl
check_tool "Helm 3    " helm
check_tool "Docker    " docker

# Check what's already installed
echo "=== Installed tools ==="
python3 --version
aws --version 2>/dev/null || echo "AWS CLI not installed"
terraform --version 2>/dev/null || echo "Terraform not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
helm version 2>/dev/null || echo "Helm not installed"
docker --version 2>/dev/null || echo "Docker not installed"

echo ""
info "AWS identity:"
aws sts get-caller-identity --output table 2>/dev/null || \
  warn "Run 'aws configure' to set credentials"

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Run ${CYAN}aws configure${NC}        — if not already done"
echo "  2. Run ${CYAN}./deploy.sh${NC}          — to deploy infrastructure"
echo "  3. Run ${CYAN}./destroy.sh${NC}         — to tear everything down"
echo ""
log "Setup complete"