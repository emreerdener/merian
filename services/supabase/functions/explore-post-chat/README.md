# explore-post-chat

Private Pro Field Chat for another user's active Explore post. Conversations are
per viewer and post, and are grounded only in the same privacy-filtered public
post projections returned by `get_explore_post` and `get_explore_post_detail`.
Only the requesting viewer can load, send, delete, or rate messages in that
conversation; it is not visible to the post author or to other viewers.

The function supports `load`, `send`, `delete`, `feedback`, and
`suggest_prompts` actions with `post_id`. It deliberately excludes owner scan
rows, media bytes or URLs, exact coordinates, comments, and owner chat history.

Explore and Insight chat share the 20-send daily allowance. Unpublishing a post
deletes its Explore chat conversations.
