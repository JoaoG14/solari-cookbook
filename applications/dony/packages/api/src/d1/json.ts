import { randomUUID } from 'node:crypto';
import type { Statement } from './client';

const referenceKey = '__dony_json_chunks';
const inlineKey = '__dony_json_inline';
const chunkBytes = 1_000_000;

// D1 caps a row at 2 MB. Keep large snapshots, attachments and model messages
// in immutable chunks; their reference is committed with the owning row.
export function encodeJson(value: string, writes: Statement[]): string {
  if (
    !value.startsWith('{') &&
    !value.startsWith('[') &&
    !value.startsWith('"')
  )
    return value;
  let parsed: any;
  try {
    parsed = JSON.parse(value);
  } catch {
    return value;
  }
  if (
    parsed &&
    typeof parsed === 'object' &&
    !Array.isArray(parsed) &&
    (referenceKey in parsed || inlineKey in parsed)
  )
    value = JSON.stringify({ [inlineKey]: parsed });
  const bytes = Buffer.from(value);
  if (bytes.length <= 500_000) return value;
  const id = randomUUID();
  for (
    let offset = 0, part = 0;
    offset < bytes.length;
    offset += chunkBytes, part += 1
  ) {
    writes.push({
      sql: 'INSERT INTO dony_json_chunks(id, part, data) VALUES (?, ?, ?)',
      params: [
        id,
        part,
        bytes.subarray(offset, offset + chunkBytes).toString('base64')
      ]
    });
  }
  // These are the only JSON fields used by SQL predicates in Dony.
  return JSON.stringify({
    [referenceKey]: id,
    parts: Math.ceil(bytes.length / chunkBytes),
    mode: parsed.mode,
    id: parsed.id
  });
}

export async function decodeJson(
  value: string,
  read: (id: string) => Promise<{ data: string }[]>
): Promise<unknown> {
  let parsed = JSON.parse(value);
  if (parsed && typeof parsed === 'object' && referenceKey in parsed) {
    const rows = await read(parsed[referenceKey]);
    if (rows.length !== parsed.parts)
      throw new Error('Dony JSON changed during the read.');
    parsed = JSON.parse(
      Buffer.concat(
        rows.map((row) => Buffer.from(row.data, 'base64'))
      ).toString()
    );
  }
  if (parsed && typeof parsed === 'object' && inlineKey in parsed)
    return parsed[inlineKey];
  return parsed;
}

export function jsonCleanupTriggers(
  table: string,
  column: string
): Statement[] {
  const oldId = `json_extract(OLD.${column}, '$.${referenceKey}')`;
  const newId = `json_extract(NEW.${column}, '$.${referenceKey}')`;
  return [
    {
      sql: `CREATE TRIGGER IF NOT EXISTS json_${table}_${column}_delete AFTER DELETE ON ${table}
      BEGIN DELETE FROM dony_json_chunks WHERE id = ${oldId}; END;`
    },
    {
      sql: `CREATE TRIGGER IF NOT EXISTS json_${table}_${column}_update AFTER UPDATE OF ${column} ON ${table}
      WHEN ${oldId} IS NOT ${newId}
      BEGIN DELETE FROM dony_json_chunks WHERE id = ${oldId}; END;`
    }
  ];
}
