.PHONY: help xcodegen validate-ios-project db-push functions-deploy

SUPABASE_WORKDIR := services

help:
	@printf "Available targets:\n"
	@printf "  make xcodegen           Regenerate Merian.xcodeproj from project.yml\n"
	@printf "  make validate-ios-project Check generated iOS project guardrails\n"
	@printf "  make db-push            Push Supabase database migrations\n"
	@printf "  make functions-deploy   Deploy all Supabase Edge Functions\n"

xcodegen:
	xcodegen generate

validate-ios-project:
	bash scripts/check-ios-project-resources.sh

db-push:
	supabase --workdir $(SUPABASE_WORKDIR) db push

functions-deploy:
	supabase --workdir $(SUPABASE_WORKDIR) functions deploy
