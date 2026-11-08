import { dirname } from "node:path";
import type { DriverSnapshot, Journal } from "./driver.ts";
/** Local append-only evidence. Existing/truncated journal is never a restart permit. */
export function fileJournal(path: string): Journal {
  let file: Deno.FsFile | undefined;
  return {
    async begin() {
      if (file) throw Error("journal_started");
      file = await Deno.open(path, {
        write: true,
        createNew: true,
        mode: 0o600,
      });
      try {
        const data = new TextEncoder().encode('{"started":true}\n');
        let offset = 0;
        while (offset < data.length) {
          const n = await file.write(data.subarray(offset));
          if (!n) throw Error("journal_write");
          offset += n;
        }
        await file.sync();
        const directory = await Deno.open(dirname(path), { read: true });
        try {
          await directory.sync();
        } finally {
          directory.close();
        }
      } finally {
        file.close();
        file = undefined;
      }
    },
    async save(snapshot: DriverSnapshot) {
      const data = new TextEncoder().encode(JSON.stringify(snapshot) + "\n");
      if (data.length > 8192) throw Error("journal_bound");
      const target = await Deno.open(path, { write: true, append: true });
      try {
        let offset = 0;
        while (offset < data.length) {
          const n = await target.write(data.subarray(offset));
          if (!n) throw Error("journal_write");
          offset += n;
        }
        await target.sync();
      } finally {
        target.close();
      }
    },
  };
}
