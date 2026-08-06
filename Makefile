.PHONY: help xcodegen validate-ios-project validate-ios-privacy-manifest validate-ios-transport-security validate-ios-versioning test-ios-project-resources test-ios-privacy-manifest test-ios-transport-security test-ios-archive-validation test-ios-exported-ipa-validation test-ios-versioning test-ios-xcode-release-workflow test-ios-ci-tooling validate-ios-migration-guardrails generate-edge-dto-contract validate-edge-dto-contract test-supabase-tooling validate-supabase-migrations test-supabase-privileged-routines audit-supabase-privileged-routines audit-ghost-users cleanup-ghost-users db-push functions-deploy

SUPABASE_WORKDIR := services

help:
	@printf "Available targets:\n"
	@printf "  make xcodegen                         Regenerate Merian.xcodeproj from project.yml\n"
	@printf "  iOS release: Product > Archive, then Organizer > Distribute App\n"
	@printf "  make validate-ios-project             Check generated iOS project guardrails\n"
	@printf "  make validate-ios-privacy-manifest    Validate app privacy declarations and required API reasons\n"
	@printf "  make validate-ios-transport-security  Enforce ATS defaults and HTTPS-only app origins\n"
	@printf "  make validate-ios-versioning          Check iOS version/build source-of-truth rules\n"
	@printf "  make test-ios-project-resources       Test adversarial generated-project phase fixtures\n"
	@printf "  make test-ios-privacy-manifest        Test privacy manifest fail-closed validation\n"
	@printf "  make test-ios-transport-security      Test ATS/HTTPS fail-closed validation\n"
	@printf "  make test-ios-archive-validation      Test archived-app privacy and ATS enforcement\n"
	@printf "  make test-ios-exported-ipa-validation Test exported-IPA privacy and ATS enforcement\n"
	@printf "  make test-ios-versioning              Run focused release-versioning script tests\n"
	@printf "  make test-ios-xcode-release-workflow  Check Xcode-only release workflow invariants\n"
	@printf "  make test-ios-ci-tooling              Test portable iOS CI workflow/result invariants\n"
	@printf "  make validate-ios-migration-guardrails Check SwiftData migration source invariants\n"
	@printf "  make generate-edge-dto-contract       Regenerate Identify Swift DTOs from the executable contract\n"
	@printf "  make validate-edge-dto-contract       Validate the Identify runtime/schema/generated-Swift contract\n"
	@printf "  make test-supabase-tooling            Run complete discovery-based Supabase tooling tests\n"
	@printf "  make validate-supabase-migrations     Check Supabase migration contracts\n"
	@printf "  make test-supabase-privileged-routines Run every checked-in Supabase pgTAP catalog locally\n"
	@printf "  make audit-supabase-privileged-routines Audit MERIAN_DATABASE_URL and fail on drift\n"
	@printf "  make audit-ghost-users ARGS='...'     Run read-only Supabase ghost-user audit\n"
	@printf "  make cleanup-ghost-users ARGS='...'   Dry-run or execute guarded ghost-user cleanup\n"
	@printf "  make db-push                          Push Supabase database migrations\n"
	@printf "  make functions-deploy                 Deploy all Supabase Edge Functions\n"

xcodegen:
	xcodegen generate

validate-ios-project:
	bash scripts/check-ios-project-resources.sh

validate-ios-privacy-manifest:
	bash scripts/validate-ios-privacy-manifest.sh

validate-ios-transport-security:
	bash scripts/validate-ios-transport-security.sh \
		apps/ios/Merian/Configuration/Info.plist \
		--allow-build-settings

validate-ios-versioning:
	bash scripts/validate-ios-versioning.sh

test-ios-project-resources:
	bash scripts/test-check-ios-project-resources.sh

test-ios-privacy-manifest:
	bash scripts/test-validate-ios-privacy-manifest.sh

test-ios-transport-security:
	bash scripts/test-validate-ios-transport-security.sh

test-ios-archive-validation:
	bash scripts/test-validate-ios-archive.sh

test-ios-exported-ipa-validation:
	bash scripts/test-validate-ios-exported-ipa.sh

test-ios-versioning:
	bash scripts/test-ios-versioning.sh

test-ios-xcode-release-workflow:
	bash scripts/test-ios-xcode-release-workflow.sh

test-ios-ci-tooling:
	bash scripts/test-check-ios-project-resources.sh
	bash scripts/test-validate-ios-privacy-manifest.sh
	bash scripts/test-validate-ios-transport-security.sh
	bash scripts/test-validate-ios-archive.sh
	bash scripts/test-validate-ios-exported-ipa.sh
	bash scripts/test-ios-versioning.sh
	bash scripts/test-ios-xcode-release-workflow.sh
	bash scripts/test-ci-detect-ios-build-source-changes.sh
	bash scripts/test-ios-build-and-test-workflow.sh
	bash scripts/test-extract-ios-test-failure-diagnostics.sh
	bash scripts/test-validate-ios-critical-test-results.sh
	bash scripts/test-validate-ios-focused-test-results.sh

validate-ios-migration-guardrails:
	bash scripts/check-ios-migration-source-guardrails.sh

generate-edge-dto-contract:
	deno run --frozen \
		--config services/supabase/scripts/validate_edge_dtos.deno.json \
		--allow-read=apps/ios \
		--allow-write=apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift \
		services/supabase/scripts/validate_edge_dtos.ts \
		--write-swift

validate-edge-dto-contract:
	bash services/supabase/scripts/validate_edge_dto_contract.sh

test-supabase-tooling:
	bash scripts/test-ci-detect-supabase-candidate-source-changes.sh
	bash services/supabase/scripts/test_supabase_tooling.sh

validate-supabase-migrations:
	bash services/supabase/scripts/validate_migration_contracts.sh

test-supabase-privileged-routines:
	bash services/supabase/scripts/require_supabase_cli_version.sh
	SUPABASE_TELEMETRY_DISABLED=1 supabase --workdir $(SUPABASE_WORKDIR) db start
	bash services/supabase/scripts/test_database_catalogs.sh

audit-supabase-privileged-routines:
	deno run --frozen --config services/supabase/functions/deno.json \
		--allow-env \
		--allow-net \
		services/supabase/scripts/audit_privileged_routine_acl.ts \
		--enforce

audit-ghost-users:
	deno run --config services/supabase/functions/deno.json \
		--allow-net --allow-env --allow-read --allow-write \
		services/supabase/scripts/audit_ghost_users.ts $(ARGS)

cleanup-ghost-users:
	deno run --config services/supabase/functions/deno.json \
		--allow-net --allow-env --allow-read --allow-write \
		services/supabase/scripts/cleanup_ghost_users.ts $(ARGS)

db-push:
	@bash services/supabase/scripts/require_supabase_cli_version.sh
	@db_url="$$(bash scripts/supabase-db-url.sh)"; \
	if [ -n "$$db_url" ]; then \
		supabase --workdir $(SUPABASE_WORKDIR) db push --db-url "$$db_url"; \
	else \
		supabase --workdir $(SUPABASE_WORKDIR) db push; \
	fi

functions-deploy:
	@bash services/supabase/scripts/require_supabase_cli_version.sh
	supabase --workdir $(SUPABASE_WORKDIR) functions deploy
