/** Private, one-use loopback review. No evidence is written to disk or logged. */
import {
  CRITERIA,
  FAIL_REASONS,
  parseRatings,
  type Ratings,
  RUBRIC,
  UNASSESSED_REASONS,
} from "./explanationContracts.ts";
import { requireCondition as check } from "./validation.ts";
export interface ReviewDisplay {
  reviewerKind?: "assistant";
  title: string;
  observation: string[];
  images: { mimeType: string; data: string }[];
  facts: string[];
  decision: string[];
  explanation: string[];
}
const CLIENT = `
const token = location.hash.slice(1); history.replaceState(null, '', '/');
let finished = false;
const main = document.querySelector('main');
const request = (path, body) => fetch(path, {method: body ? 'POST' : 'GET', cache: 'no-store', credentials: 'omit', headers: {'X-Review-Token': token, ...(body ? {'Content-Type': 'application/json'} : {})}, ...(body ? {body: JSON.stringify(body)} : {})});
function add(tag, value, parent=main) { const e = document.createElement(tag); e.textContent=value; parent.append(e); return e; }
async function start() {
 const response=await request('/view'); if(!response.ok) throw Error(); const v=await response.json();
 main.replaceChildren(); add('h1',v.title); add('p',v.reviewerKind === 'assistant' ? 'AI-assisted development review. Compare the explanation with the supplied evidence. Only ratings enter evaluation files; the displayed content is processed in the assistant session. Do not export the page.' : 'Review the explanation against this evidence. Saved results contain your ratings only. Do not save or record this page.');
 for(const [name, items] of [['Observation',v.observation],['Reviewed facts and requirements',v.facts],['Decision',v.decision],['Explanation',v.explanation]]) {if(!items.length) continue; add('h2',name); for(const item of items) add('p',item);}
 for(const item of v.images) {const img=document.createElement('img'); img.alt='Supplied observation'; img.src='data:'+item.mimeType+';base64,'+item.data; main.append(img);}
 const form=document.createElement('form'); main.append(form);
 for(const key of v.criteria) {const label=add('label',v.rubric[key],form); const select=document.createElement('select'); select.name=key; select.required=true; label.append(select); const blank=add('option','Choose a rating',select); blank.value='';
 for(const option of [{status:'pass',reason:'supported'},...v.fail[key].map(reason=>({status:'fail',reason})),...v.unassessed.map(reason=>({status:'not_assessable',reason}))]) {const o=add('option',option.status.replaceAll('_',' ')+' — '+option.reason.replaceAll('_',' '),select); o.value=JSON.stringify(option);}}
 const submit=add('button','Save ratings',form); submit.type='submit';
 form.onsubmit=async e=>{e.preventDefault(); submit.disabled=true; try {const ratings=Object.fromEntries(v.criteria.map(k=>[k,JSON.parse(form.elements.namedItem(k).value)])); const r=await request('/submit',ratings); if(!r.ok) throw Error(); finished=true; main.replaceChildren(); add('p','Ratings recorded. You can close this tab.');} catch {finished=true; main.replaceChildren(); add('p','Review ended without a confirmed save. Check the local run status.');}};
}
addEventListener('pagehide',()=>{if(!finished) navigator.sendBeacon('/cancel',JSON.stringify({token})); main.replaceChildren();});
start().catch(()=>{main.replaceChildren();add('p','This private review is unavailable or has ended.');});
`;
const headers = (type = "text/plain") => ({
  "content-type": `${type}; charset=utf-8`,
  "cache-control": "no-store, max-age=0",
  "pragma": "no-cache",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "cross-origin-resource-policy": "same-origin",
});
async function boundedJson(request: Request) {
  check(request.body !== null);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  const timer = setTimeout(() => void reader.cancel(), 2000);
  try {
    while (true) {
      const r = await reader.read();
      if (r.done) break;
      length += r.value.length;
      check(length <= 4096);
      chunks.push(r.value);
    }
  } finally {
    clearTimeout(timer);
    await reader.cancel();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const c of chunks) {
    bytes.set(c, offset);
    offset += c.length;
  }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}
/** Check local UI capability before the controller can claim a paid request. */
export async function assertPrivateReviewReady() {
  check(Deno.build.os === "darwin");
  check(
    (await Deno.permissions.query({ name: "net", host: "127.0.0.1" })).state ===
      "granted",
  );
  check(
    (await Deno.permissions.query({ name: "run", command: "/usr/bin/open" }))
      .state === "granted",
  );
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  listener.close();
}
/** Pure handler for transport/security tests; returned display data is ephemeral. */
export function reviewSession(
  initial: ReviewDisplay,
  origin: () => string,
  secret: string,
) {
  let display: ReviewDisplay | null = initial, ended = false;
  let complete!: (ratings: Ratings | null) => void;
  const result = new Promise<Ratings | null>((resolve) => {
    complete = resolve;
  });
  const close = () => {
    if (!ended) {
      ended = true;
      display = null;
      complete(null);
    }
  };
  const reply = (body: string, status = 200, type = "text/plain") =>
    new Response(body, { status, headers: headers(type) });
  const handler = async (request: Request): Promise<Response> => {
    try {
      const url = new URL(request.url);
      if (url.origin !== origin() || request.headers.get("host") !== url.host) {
        return reply("Unavailable", 403);
      }
      if (request.method === "GET" && url.pathname === "/") {
        const nonce = crypto.randomUUID().replaceAll("-", "");
        const h = {
          ...headers("text/html"),
          "content-security-policy":
            `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
        };
        return new Response(
          `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Naturebook explanation review</title><style>body{font:17px system-ui;max-width:860px;margin:40px auto;padding:24px}p{white-space:pre-wrap}img{max-width:100%;max-height:600px}label,select{display:block;margin:20px 0}select,button{font:inherit;padding:12px;width:100%}</style><main>Opening private review…</main><script nonce="${nonce}">${CLIENT}</script></html>`,
          { headers: h },
        );
      }
      if (ended) return reply("Review ended", 410);
      if (request.method === "POST" && url.pathname === "/cancel") {
        if (request.headers.get("origin") !== origin()) {
          return reply("Unavailable", 403);
        }
        const v = await boundedJson(request);
        if (v?.token !== secret) return reply("Unavailable", 403);
        close();
        return reply("Closed");
      }
      if (request.headers.get("x-review-token") !== secret) {
        return reply("Unavailable", 403);
      }
      if (request.method === "GET" && url.pathname === "/view") {
        return reply(
          JSON.stringify({
            ...display,
            criteria: CRITERIA,
            rubric: RUBRIC.criteria,
            fail: FAIL_REASONS,
            unassessed: UNASSESSED_REASONS,
          }),
          200,
          "application/json",
        );
      }
      if (request.method === "POST" && url.pathname === "/submit") {
        if (
          request.headers.get("origin") !== origin() ||
          request.headers.get("content-type") !== "application/json"
        ) return reply("Unavailable", 403);
        const ratings = parseRatings(await boundedJson(request));
        if (ended) return reply("Review ended", 410);
        ended = true;
        display = null;
        complete(ratings);
        return reply("Recorded");
      }
      return reply("Unavailable", 404);
    } catch {
      return reply("Invalid review", 400);
    }
  };
  return { handler, result, close };
}
/** Fixed opener, scrubbed child environment. Neither URL capability nor content is logged. */
export async function openPrivateReview(
  display: ReviewDisplay,
  timeoutMs: number,
): Promise<Ratings | null> {
  check(
    Number.isSafeInteger(timeoutMs) && timeoutMs >= 1000 && timeoutMs <= 600000,
  );
  const abort = new AbortController();
  let origin = "";
  const secret = Array.from(
    crypto.getRandomValues(new Uint8Array(32)),
    (n) => n.toString(16).padStart(2, "0"),
  ).join("");
  const session = reviewSession(display, () => origin, secret);
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    signal: abort.signal,
    onListen() {},
    onError: () =>
      new Response("Review unavailable", { status: 500, headers: headers() }),
  }, session.handler);
  origin = `http://127.0.0.1:${server.addr.port}`;
  const timer = setTimeout(session.close, timeoutMs);
  try {
    const opened = await new Deno.Command("/usr/bin/open", {
      args: [`${origin}/#${secret}`],
      clearEnv: true,
      stdin: "null",
      stdout: "null",
      stderr: "null",
    }).output();
    if (!opened.success) return null;
    return await session.result;
  } finally {
    session.close();
    clearTimeout(timer);
    const force = setTimeout(() => abort.abort(), 3000);
    try {
      await server.shutdown();
      await server.finished;
    } finally {
      clearTimeout(force);
    }
  }
}
