#!/usr/bin/env bash
# Instala as CLIs dos agentes de IA e configura o ambiente do workspace.
# Uso: bash scripts/setup-agents.sh   (tambem roda no postStart do devfile)
#
# As chaves NAO ficam neste repositorio: chegam como variaveis de ambiente pelo
# Secret 'agents-env' (ver README-AGENTS.md). O .env.local so e usado como
# alternativa se existir em $HOME/.env.local (storage efemero: some ao parar).
set -uo pipefail

NPM_PREFIX="$HOME/.npm-global"
BASHRC="$HOME/.bashrc"
ENV_FILE="$HOME/.env.local"
ICA_BASE_URL="https://api.servicesessentials.ibm.com/v1"

# Pacote npm -> comando
PACKAGES=(
  "@anthropic-ai/claude-code"  # claude
  "@openai/codex"              # codex
  "opencode-ai"                # opencode
  "cline"                      # cline
)

if ! command -v npm >/dev/null 2>&1; then
  echo "x npm nao encontrado; instale o Node.js antes." >&2
  exit 1
fi

# Prefixo em $HOME evita erro de permissao no npm install -g
mkdir -p "$NPM_PREFIX/bin"
export PATH="$NPM_PREFIX/bin:$PATH"

for pkg in "${PACKAGES[@]}"; do
  if npm install -g --prefix "$NPM_PREFIX" "$pkg" >/dev/null 2>&1; then
    echo "ok $pkg"
  else
    echo "x  $pkg (falhou; rode 'npm install -g --prefix $NPM_PREFIX $pkg' para ver o erro)" >&2
  fi
done

# PATH e carga opcional do ~/.env.local em todo terminal novo (idempotente)
MARK="# >>> setup-agents >>>"
if ! grep -qF "$MARK" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<EOF

$MARK
export PATH="$NPM_PREFIX/bin:\$PATH"
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
# <<< setup-agents <<<
EOF
  echo "ok .bashrc atualizado"
fi

# Claude Code: pula a tela de login (usa ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL)
[ -f "$HOME/.claude.json" ] || echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"

# Codex ignora OPENAI_BASE_URL: precisa de um provider apontando para o gateway ICA
mkdir -p "$HOME/.codex"
cat > "$HOME/.codex/config.toml" <<EOF
model = "gpt-5.1"
model_provider = "ica"

[model_providers.ica]
name = "ICA Gateway"
base_url = "$ICA_BASE_URL"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
EOF
echo "ok ~/.codex/config.toml"

# OpenCode: provider proprio apontando para o gateway ICA (chave via OPENCODE_API_KEY)
mkdir -p "$HOME/.config/opencode"
cat > "$HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "ica": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "ICA Gateway",
      "options": {
        "baseURL": "$ICA_BASE_URL",
        "apiKey": "{env:OPENCODE_API_KEY}"
      },
      "models": {
        "gpt-5.1": { "name": "GPT 5.1" },
        "claude-sonnet-5-5": { "name": "Claude Sonnet 5.5" },
        "claude-haiku-5-5": { "name": "Claude Haiku 5.5" }
      }
    }
  },
  "model": "ica/gpt-5.1"
}
EOF
echo "ok ~/.config/opencode/opencode.json"

# Cline: provider openai-compatible apontando para o gateway ICA (chave via CLINE_API_KEY)
if [ -n "${CLINE_API_KEY:-}" ]; then
  if "$NPM_PREFIX/bin/cline" auth -p openai -k "$CLINE_API_KEY" -m gpt-5.1 -b "$ICA_BASE_URL" >/dev/null 2>&1; then
    echo "ok cline auth (gateway ICA, gpt-5.1)"
  else
    echo "x  cline auth falhou; rode: cline auth -p openai -k \$CLINE_API_KEY -m gpt-5.1 -b $ICA_BASE_URL" >&2
  fi
fi

# Roo Code: perfil OpenAI Compatible apontando para o gateway /apis/v3 da IBM Services
# Essentials. Gera ~/Downloads/roo-code-settings.json (contem a chave, so no pod; nao
# versionar) para importar no Roo: Settings > Import. Chave via ROO_API_KEY.
if [ -n "${ROO_API_KEY:-}" ]; then
  mkdir -p "$HOME/Downloads"
  python3 - <<'PY'
import json, os
base = os.environ.get("ROO_BASE_URL", "https://servicesessentials.ibm.com/apis/v3")
model = os.environ.get("ROO_MODEL", "global/gpt-5.1-chat")
cfg = {
    "id": "ica-gateway-profile",
    "apiProvider": "openai",
    "openAiBaseUrl": base,
    "openAiApiKey": os.environ["ROO_API_KEY"],
    "openAiModelId": model,
    "openAiStreamingEnabled": True,
    "openAiCustomModelInfo": {
        "maxTokens": -1, "contextWindow": 128000, "supportsImages": False,
        "supportsPromptCache": False, "inputPrice": 0, "outputPrice": 0,
    },
}
out = {
    "providerProfiles": {
        "currentApiConfigName": "ica-gateway",
        "apiConfigs": {"ica-gateway": cfg},
        "modeApiConfigs": {},
        "migrations": {"rateLimitSecondsMigrated": True, "diffSettingsMigrated": True,
                       "openAiHeadersMigrated": True, "consecutiveMistakeLimitMigrated": True,
                       "todoListEnabledMigrated": True},
    },
    "globalSettings": {"mode": "code"},
}
p = os.path.expanduser("~/Downloads/roo-code-settings.json")
with open(p, "w") as f:
    json.dump(out, f, indent=2)
os.chmod(p, 0o600)
PY
  echo "ok ~/Downloads/roo-code-settings.json (importe no Roo: Settings > Import)"
else
  echo "!  ROO_API_KEY NAO definida; perfil do Roo nao gerado" >&2
fi

# Verifica se o Secret foi montado (so mostra nomes, nunca valores)
for v in ANTHROPIC_API_KEY OPENAI_API_KEY OPENCODE_API_KEY CLINE_API_KEY ROO_API_KEY; do
  if [ -n "${!v:-}" ]; then echo "ok $v definida"; else echo "!  $v NAO definida (Secret agents-env nao montado?)" >&2; fi
done

echo "Feito. Abra um novo terminal ou rode: source ~/.bashrc"
echo "Comandos: claude | codex | opencode | cline"
