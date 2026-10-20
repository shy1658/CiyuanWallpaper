/**
 * 字符串哈希工具（用于生成本地 ID）
 */
export function hashString(input: string): string {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < input.length; i++) {
    const ch = input.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
  h2 = Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  const hex1 = (h2 >>> 0).toString(16).padStart(8, '0');
  const hex2 = (h1 >>> 0).toString(16).padStart(8, '0');
  return hex1 + hex2;
}
