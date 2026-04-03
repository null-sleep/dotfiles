## START OF BITGO CONFIG

# Put python packages in $PATH
PATH=$HOME/Library/Python/3.9/bin:$PATH

# Setup gpg-agent for ssh use
ENVFILE="$HOME/.gnupg/gpg-agent.env"

if ( [[ ! -e "$HOME/.gnupg/S.gpg-agent" ]] && \
     [[ ! -e "/var/run/user/$(id -u)/gnupg/S.gpg-agent" ]] ) ||
   ( [[ ! -s "$ENVFILE" ]] );
then
  if [[ ! -d "$HOME/.gnupg" ]]; then
    echo 'Create ~/.gnupg directory'
    mkdir -m 700 "$HOME/.gnupg"
  fi
  if [[ ! -f "$HOME/.gnupg/gpg-agent.conf" ]]; then
    echo 'Set pinentry-mac to default gpg pinentry in ~/.gnupg/gpg-agent.conf'
    echo "pinentry-program /opt/homebrew/bin/pinentry-mac" > "$HOME/.gnupg/gpg-agent.conf"
  fi

  echo "Reloading scdaemon and gpg-agent, creating .env file: $ENVFILE"
  killall pinentry > /dev/null 2>&1
  gpgconf --reload scdaemon > /dev/null 2>&1
  killall -9 gpg-agent > /dev/null 2>&1
  gpg-agent --daemon --enable-ssh-support > "$ENVFILE"
fi

# Wake up smartcard to avoid races
gpg --card-status > /dev/null 2>&1

source "$ENVFILE"

# Setup nvm
if [[ ! -d "$HOME/.nvm" ]]; then
  mkdir ~/.nvm
fi
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"

# add alias to use git from Homebrew
alias git="/opt/homebrew/bin/git"

## END OF BITGO CONFIG


export PATH="${HOMEBREW_PREFIX}/opt/openssl/bin:$PATH"
export PATH="${HOMEBREW_PREFIX}/opt/openssl/bin:$PATH"

# From: https://bitgoinc.atlassian.net/wiki/spaces/ENG/pages/3352035357/How+to+Authenticate+npm+with+AWS+CodeArtifact
function codeartifact-login() {
  echo "Attempting to login to AWS CodeArtifact..."
  # Loads the AWS CodeArtifact token into the environment as AWS_CODEARTIFACT_TOKEN
  export AWS_CODEARTIFACT_TOKEN=$(
    aws --profile dev codeartifact get-authorization-token \
      --region us-west-2 \
      --domain private \
      --domain-owner 199765120567 \
      --query authorizationToken \
      --output text
  )
  if [[ -z "${AWS_CODEARTIFACT_TOKEN}" ]]; then
    echo "Failed to login to AWS CodeArtifact. Check if AWS CLI is configured"
  else
    echo "Successfully logged in to AWS CodeArtifact, token expires in 12 hours"
  fi
}

codeartifact-login

function update-claude() {
    nix profile remove --regex '.*claude-code'
    nix profile install --refresh github:bitgo/bitgopkgs#claude-code
}

alias yoloRun="make reset-database && make generate-database-models && make generate-graphql-models && make run-server"
alias portForward="KUBE_CONTEXT=test3 KUBE_NAMESPACE=staging-microservices ~/Dev/trade-services/packages/lumina-server-shared/scripts/kube_port_forward.sh"
alias start-db="cd ~/src/trade-services/packages/lumina-server-shared && make docker-up"
alias start-server="cd ~/src/trade-services/packages/lumina-server-shared && make run-server"

# Trade repo
## BitGo Go Setup
export GOPRIVATE=github.com/lumina-tech/*,github.com/bitgo/*

# export PATH=$HOME/bin:/usr/local/bin:/usr/local/go/bin:$PATH

# Lumina Node
# export NVM_DIR="$HOME/.nvm"
# [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
# [ -s "/usr/local/opt/nvm/etc/bash_completion" ] && . "/usr/local/opt/nvm/etc/bash_completion"  # This     loads nvm bash_completion

# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix

# Import my personal configs
source /Users/dhruvjauhar/.zshrc_config.zsh
