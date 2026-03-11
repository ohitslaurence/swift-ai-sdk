#!/usr/bin/env bash
#
# Fetches model IDs from models.dev and compares them against the model
# constants defined in this package. Use this to identify missing or
# incorrect model IDs before updating OpenAIModels.swift or
# AnthropicModels.swift.
#
# Usage:
#   ./Tools/sync-models.sh           # show all models from both providers
#   ./Tools/sync-models.sh openai    # show only OpenAI models
#   ./Tools/sync-models.sh anthropic # show only Anthropic models
#   ./Tools/sync-models.sh diff      # compare models.dev vs local constants

set -euo pipefail

API_URL="https://models.dev/api.json"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPENAI_FILE="$ROOT_DIR/Sources/AIProviderOpenAI/OpenAIModels.swift"
ANTHROPIC_FILE="$ROOT_DIR/Sources/AIProviderAnthropic/AnthropicModels.swift"

fetch_models() {
    curl -s "$API_URL"
}

extract_provider_models() {
    local provider="$1"
    local json="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
provider = data.get('$provider', {})
models = provider.get('models', {})
for model_id in sorted(models.keys()):
    print(model_id)
"
}

extract_local_models() {
    local file="$1"
    grep -oE '"[^"]+", provider:' "$file" | sed 's/", provider://' | sed 's/"//' | sort
}

case "${1:-all}" in
    openai)
        echo "=== OpenAI models from models.dev ==="
        JSON=$(fetch_models)
        extract_provider_models "openai" "$JSON"
        ;;
    anthropic)
        echo "=== Anthropic models from models.dev ==="
        JSON=$(fetch_models)
        extract_provider_models "anthropic" "$JSON"
        ;;
    diff)
        JSON=$(fetch_models)

        echo "=== OpenAI ==="
        echo ""
        echo "models.dev:"
        REMOTE_OPENAI=$(extract_provider_models "openai" "$JSON")
        echo "$REMOTE_OPENAI"
        echo ""
        echo "Local (OpenAIModels.swift):"
        LOCAL_OPENAI=$(extract_local_models "$OPENAI_FILE")
        echo "$LOCAL_OPENAI"
        echo ""
        echo "In models.dev but NOT in local:"
        comm -23 <(echo "$REMOTE_OPENAI") <(echo "$LOCAL_OPENAI") || true
        echo ""
        echo "In local but NOT in models.dev:"
        comm -13 <(echo "$REMOTE_OPENAI") <(echo "$LOCAL_OPENAI") || true

        echo ""
        echo "=== Anthropic ==="
        echo ""
        echo "models.dev:"
        REMOTE_ANTHROPIC=$(extract_provider_models "anthropic" "$JSON")
        echo "$REMOTE_ANTHROPIC"
        echo ""
        echo "Local (AnthropicModels.swift):"
        LOCAL_ANTHROPIC=$(extract_local_models "$ANTHROPIC_FILE")
        echo "$LOCAL_ANTHROPIC"
        echo ""
        echo "In models.dev but NOT in local:"
        comm -23 <(echo "$REMOTE_ANTHROPIC") <(echo "$LOCAL_ANTHROPIC") || true
        echo ""
        echo "In local but NOT in models.dev:"
        comm -13 <(echo "$REMOTE_ANTHROPIC") <(echo "$LOCAL_ANTHROPIC") || true
        ;;
    all|*)
        JSON=$(fetch_models)
        echo "=== OpenAI models from models.dev ==="
        extract_provider_models "openai" "$JSON"
        echo ""
        echo "=== Anthropic models from models.dev ==="
        extract_provider_models "anthropic" "$JSON"
        ;;
esac
