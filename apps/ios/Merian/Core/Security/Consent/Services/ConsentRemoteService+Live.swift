import Supabase

extension ConsentRemoteService {
    static var live: Self {
        Self(dependencies: .live)
    }
}

extension ConsentRemoteService.Dependencies {
    static var live: Self {
        Self(
            insertAdultEligibilityReceipt: { row in
                _ = try await SupabaseManager.shared.client
                    .from("user_adult_eligibility_receipts")
                    .insert(row)
                    .execute()
            },
            insertTermsReceipt: { row in
                _ = try await SupabaseManager.shared.client
                    .from("user_terms_acceptance_receipts")
                    .insert(row)
                    .execute()
            },
            appendAIConsentEvent: { parameters in
                try await SupabaseManager.shared.client
                    .rpc(
                        "append_user_ai_consent_event",
                        params: parameters
                    )
                    .execute()
                    .value
            },
            appendAnalyticsConsentEvent: { parameters in
                try await SupabaseManager.shared.client
                    .rpc(
                        "append_user_analytics_consent_event",
                        params: parameters
                    )
                    .execute()
                    .value
            },
            fetchAdultEligibilityReceipt: { id, userId in
                try await SupabaseManager.shared.client
                    .from("user_adult_eligibility_receipts")
                    .select(ConsentRemoteWire.adultEligibilityReceiptColumns)
                    .eq("id", value: id)
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
            },
            fetchTermsReceipt: { id, userId in
                try await SupabaseManager.shared.client
                    .from("user_terms_acceptance_receipts")
                    .select(ConsentRemoteWire.termsReceiptColumns)
                    .eq("id", value: id)
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
            },
            fetchAIConsentEvent: { id, userId in
                try await SupabaseManager.shared.client
                    .from("user_ai_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("id", value: id)
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
            },
            fetchAnalyticsConsentEvent: { id, userId in
                try await SupabaseManager.shared.client
                    .from("user_analytics_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("id", value: id)
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
            },
            fetchRemoteRows: { userId in
                async let adultRows: [ConsentRemoteWire.AdultEligibilityReceipt] =
                    SupabaseManager.shared.client
                    .from("user_adult_eligibility_receipts")
                    .select(ConsentRemoteWire.adultEligibilityReceiptColumns)
                    .eq("user_id", value: userId)
                    .eq(
                        "policy_version",
                        value: ConsentPolicy.adultEligibilityVersion
                    )
                    .order("recorded_at", ascending: false)
                    .order("id", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                async let termsRows: [ConsentRemoteWire.TermsReceipt] =
                    SupabaseManager.shared.client
                    .from("user_terms_acceptance_receipts")
                    .select(ConsentRemoteWire.termsReceiptColumns)
                    .eq("user_id", value: userId)
                    .eq("terms_version", value: ConsentPolicy.termsVersion)
                    .order("recorded_at", ascending: false)
                    .order("id", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                async let aiRows: [ConsentRemoteWire.AIConsentEvent] =
                    SupabaseManager.shared.client
                    .from("user_ai_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("user_id", value: userId)
                    .eq("provider", value: ConsentPolicy.geminiProvider)
                    .eq(
                        "disclosure_version",
                        value: ConsentPolicy.geminiDisclosureVersion
                    )
                    .order("consent_revision", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                async let analyticsRows: [ConsentRemoteWire.AnalyticsConsentEvent] =
                    SupabaseManager.shared.client
                    .from("user_analytics_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("user_id", value: userId)
                    .eq("provider", value: ConsentPolicy.analyticsProvider)
                    .eq(
                        "disclosure_version",
                        value: ConsentPolicy.analyticsDisclosureVersion
                    )
                    .order("consent_revision", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                // A prior disclosure may still own the stream head. Fetch it
                // independently so the next action carries its true parent.
                async let aiStreamHeadRows: [ConsentRemoteWire.AIConsentEvent] =
                    SupabaseManager.shared.client
                    .from("user_ai_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("user_id", value: userId)
                    .eq("provider", value: ConsentPolicy.geminiProvider)
                    .order("consent_revision", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                async let analyticsStreamHeadRows:
                    [ConsentRemoteWire.AnalyticsConsentEvent] =
                    SupabaseManager.shared.client
                    .from("user_analytics_consent_events")
                    .select(ConsentRemoteWire.consentEventColumns)
                    .eq("user_id", value: userId)
                    .eq("provider", value: ConsentPolicy.analyticsProvider)
                    .order("consent_revision", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                let rows = try await (
                    adultRows,
                    termsRows,
                    aiRows,
                    analyticsRows,
                    aiStreamHeadRows,
                    analyticsStreamHeadRows
                )
                return ConsentRemoteWire.RemoteRows(
                    adultEligibilityReceipts: rows.0,
                    termsReceipts: rows.1,
                    aiConsentEvents: rows.2,
                    analyticsConsentEvents: rows.3,
                    aiConsentStreamHeads: rows.4,
                    analyticsConsentStreamHeads: rows.5
                )
            }
        )
    }
}
