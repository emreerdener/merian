.PHONY: help xcodegen validate-ios-project validate-ios-migration-guardrails validate-supabase-migrations db-push functions-deploy

SUPABASE_WORKDIR := services

help:
	@printf "Available targets:\n"
	@printf "  make xcodegen           Regenerate Merian.xcodeproj from project.yml\n"
	@printf "  make validate-ios-project Check generated iOS project guardrails\n"
	@printf "  make validate-ios-migration-guardrails Check SwiftData migration source invariants\n"
	@printf "  make validate-supabase-migrations Check Supabase migration contracts\n"
	@printf "  make db-push            Push Supabase database migrations\n"
	@printf "  make functions-deploy   Deploy all Supabase Edge Functions\n"

xcodegen:
	xcodegen generate

validate-ios-project:
	bash scripts/check-ios-project-resources.sh

validate-ios-migration-guardrails:
	bash scripts/check-ios-migration-source-guardrails.sh

validate-supabase-migrations:
	deno test --config services/supabase/functions/deno.json \
		--allow-read=services/supabase/migrations \
		services/supabase/functions/_tests/migrationMediaContract.test.ts

db-push:
	@db_url="$$(bash scripts/supabase-db-url.sh)"; \
	if [ -n "$$db_url" ]; then \
		supabase --workdir $(SUPABASE_WORKDIR) db push --db-url "$$db_url"; \
	else \
		supabase --workdir $(SUPABASE_WORKDIR) db push; \
	fi

functions-deploy:
	supabase --workdir $(SUPABASE_WORKDIR) functions deploy
