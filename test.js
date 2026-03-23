const e1 = "Missing structural boundary (neither r2ObjectKeys nor imageBase64s provided).";
const e2 = "Unauthorized: Invalid or missing User IDFV. Scans cannot be saved without a physical Device ID.";

console.log(Buffer.byteLength(JSON.stringify({ error: e1 })));
console.log(Buffer.byteLength(JSON.stringify({ error: e2 })));
