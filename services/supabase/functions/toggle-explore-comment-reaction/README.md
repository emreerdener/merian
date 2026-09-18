# Legacy comment reaction toggle

Retained for older native clients. Authentication and catalog validation precede
the guarded transactional `toggle_explore_comment_reaction` RPC. New clients use
`set-explore-comment-reaction` with an explicit selected state so retries are
idempotent. Existing stored reactions remain intact; known presentation aliases
share one displayed identity.

See [API contracts](../../../../docs/backend-and-data/05-api-contracts.md).
