import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const deploymentWorkflow = await Deno.readTextFile(
  new URL("../../../../.github/workflows/deploy.yml", import.meta.url),
);

Deno.test("production smoke proves the public-web Explore credential boundary", () => {
  for (
    const expected of [
      "/rest/v1/rpc/get_public_web_explore_posts",
      "public-web-explore-rpc-denied-${index}.json",
      "401 | 403 | 404",
      "A public Supabase API credential unexpectedly executed",
      "public_web_explore_response",
      "post_server_json",
      ".like_count == 0",
      ".comment_count == 0",
      ".viewer_has_liked == false",
      ".is_owned_by_viewer == false",
    ]
  ) {
    assertStringIncludes(deploymentWorkflow, expected);
  }

  const negativeControl = deploymentWorkflow.slice(
    deploymentWorkflow.indexOf(
      'explore_denied_response="$RUNNER_TEMP/public-web-explore',
    ),
    deploymentWorkflow.indexOf(
      "done",
      deploymentWorkflow.indexOf(
        'explore_denied_response="$RUNNER_TEMP/public-web-explore',
      ),
    ),
  );
  assertStringIncludes(negativeControl, '"${public_headers[@]}"');
  assertEquals(negativeControl.includes("server_headers"), false);

  const positiveControl = deploymentWorkflow.slice(
    deploymentWorkflow.indexOf('public_web_explore_response="$('),
    deploymentWorkflow.indexOf(
      'owned_incidents_response="$(',
      deploymentWorkflow.indexOf('public_web_explore_response="$('),
    ),
  );
  assertStringIncludes(positiveControl, "post_server_json");
  assertEquals(positiveControl.includes("public_headers"), false);
});
