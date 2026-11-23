export function frame(metadata: unknown, bytes: Uint8Array) {
  const json = new TextEncoder().encode(JSON.stringify(metadata));
  const body = new Uint8Array(4 + json.length + bytes.length);
  new DataView(body.buffer).setUint32(0, json.length);
  body.set(json, 4);
  body.set(bytes, 4 + json.length);
  return body;
}
