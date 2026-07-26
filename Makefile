.PHONY: help xcodegen prepare-ios-release export-ios-release validate-ios-project validate-ios-versioning test-ios-versioning validate-ios-migration-guardrails validate-edge-dto-contract test-supabase-tooling validate-supabase-migrations test-supabase-privileged-routines audit-supabase-privileged-routines audit-ghost-users cleanup-ghost-users db-push functions-deploy

SUPABASE_WORKDIR := services

help:
	@printf "Available targets:\n"
	@printf "  make xcodegen                         Regenerate Merian.xcodeproj from project.yml\n"
	@printf "  make prepare-ios-release VERSION=x.y.z Prepare a TestFlight release version/build\n"
	@printf "  make export-ios-release               Export the latest prepared archive for App Store Connect\n"
	@printf "  make validate-ios-project             Check generated iOS project guardrails\n"
	@printf "  make validate-ios-versioning          Check iOS version/build source-of-truth rules\n"
	@printf "  make test-ios-versioning              Run focused release-versioning script tests\n"
	@printf "  make validate-ios-migration-guardrails Check SwiftData migration source invariants\n"
	@printf "  make validate-edge-dto-contract       Validate Identify schema against the complete iOS DTO source graph\n"
	@printf "  make test-supabase-tooling            Run complete discovery-based Supabase tooling tests\n"
	@printf "  make validate-supabase-migrations     Check Supabase migration contracts\n"
	@printf "  make test-supabase-privileged-routines Validate privileged-routine, account-deletion, Ghost-merge, AI-quota, DwC-A, RevenueCat, species-stats, and waitlist catalogs locally\n"
	@printf "  make audit-supabase-privileged-routines Audit MERIAN_DATABASE_URL and fail on drift\n"
	@printf "  make audit-ghost-users ARGS='...'     Run read-only Supabase ghost-user audit\n"
	@printf "  make cleanup-ghost-users ARGS='...'   Dry-run or execute guarded ghost-user cleanup\n"
	@printf "  make db-push                          Push Supabase database migrations\n"
	@printf "  make functions-deploy                 Deploy all Supabase Edge Functions\n"

xcodegen:
	xcodegen generate

prepare-ios-release:
	bash scripts/prepare-ios-release.sh

export-ios-release:
	bash scripts/export-ios-release.sh

validate-ios-project:
	bash scripts/check-ios-project-resources.sh

validate-ios-versioning:
	bash scripts/validate-ios-versioning.sh

test-ios-versioning:
	bash scripts/test-ios-versioning.sh

validate-ios-migration-guardrails:
	bash scripts/check-ios-migration-source-guardrails.sh

validate-edge-dto-contract:
	bash services/supabase/scripts/validate_edge_dto_contract.sh

test-supabase-tooling:
	bash services/supabase/scripts/test_supabase_tooling.sh

validate-supabase-migrations:
	deno test --config services/supabase/functions/deno.json \
		--allow-read=services/supabase/migrations \
		services/supabase/functions/_tests/accountDeletionMigrationContract.test.ts \
		services/supabase/functions/_tests/aiQuotaMigrationContract.test.ts \
		services/supabase/functions/_tests/completeEdgeDatabaseRepairMigrationContract.test.ts \
		services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts \
		services/supabase/functions/_tests/exploreMediaQuarantineMigrationContract.test.ts \
		services/supabase/functions/_tests/jsonEndpointSecurityMigrationContract.test.ts \
		services/supabase/functions/_tests/migrationExecutionContract.test.ts \
		services/supabase/functions/_tests/migrationMediaContract.test.ts \
		services/supabase/functions/_tests/privilegedRoutineMigrationContract.test.ts \
		services/supabase/functions/_tests/revenueCatWebhookMigrationContract.test.ts \
		services/supabase/functions/_tests/speciesCountTriggerMigrationContract.test.ts \
		services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts

test-supabase-privileged-routines:
	supabase --workdir $(SUPABASE_WORKDIR) db start
	supabase --workdir $(SUPABASE_WORKDIR) db push --local
	supabase --workdir $(SUPABASE_WORKDIR) test db --local \
		services/supabase/tests/account_deletion_security.sql \
		services/supabase/tests/explore_media_quarantine_security.sql \
		services/supabase/tests/ghost_profile_merge_security.sql \
		services/supabase/tests/privileged_routine_security.sql \
		services/supabase/tests/ai_quota_security.sql \
		services/supabase/tests/export_dwca_security.sql \
		services/supabase/tests/revenuecat_webhook_security.sql \
		services/supabase/tests/species_count_trigger_security.sql \
		services/supabase/tests/species_observation_stats_security.sql \
		services/supabase/tests/waitlist_security.sql

audit-supabase-privileged-routines:
	deno run --frozen --config services/supabase/functions/deno.json \
		--allow-env \
		--allow-net \
		services/supabase/scripts/audit_privileged_routine_acl.ts \
		--enforce

audit-ghost-users:
	deno run --allow-net --allow-env --allow-read --allow-write \
		services/supabase/scripts/audit_ghost_users.ts $(ARGS)

cleanup-ghost-users:
	deno run --allow-net --allow-env --allow-read --allow-write \
		services/supabase/scripts/cleanup_ghost_users.ts $(ARGS)

db-push:
	@db_url="$$(bash scripts/supabase-db-url.sh)"; \
	if [ -n "$$db_url" ]; then \
		supabase --workdir $(SUPABASE_WORKDIR) db push --db-url "$$db_url"; \
	else \
		supabase --workdir $(SUPABASE_WORKDIR) db push; \
	fi

functions-deploy:
	supabase --workdir $(SUPABASE_WORKDIR) functions deploy
