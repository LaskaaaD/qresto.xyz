.PHONY: validate test audit compose-config

validate:
	bash scripts/validate.sh

test:
	cd app && npm test

audit:
	cd app && npm audit --audit-level=moderate

compose-config:
	bash -c 'set -euo pipefail; created=0; if [ ! -f .env ]; then cp .env.example .env; created=1; fi; trap "if [ $$created -eq 1 ]; then rm -f .env; fi" EXIT; docker compose --env-file .env -f docker-compose.yml config >/dev/null'
