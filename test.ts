const req = new Request("http://localhost", { method: "POST", body: "{ invalid " });
try {
  await req.json();
} catch (e) {
  console.log(e.message);
  console.log(JSON.stringify({ error: e.message }).length);
}
