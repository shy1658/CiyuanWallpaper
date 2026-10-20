import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/**
 * MD5 工具（CryptoArchitectureKit 实现）。
 * 用于与原版次元壁纸服务端（api.awsl.13th.tech）的请求签名。
 */

/** 字节数组转小写十六进制字符串 */
function bytesToHex(bytes: Uint8Array): string {
  const hex: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const b: number = bytes[i];
    out += hex.charAt((b >> 4) & 0xf) + hex.charAt(b & 0xf);
  }
  return out;
}

/** 计算字符串（UTF-8）的 MD5 十六进制摘要 */
export function md5Hex(input: string): string {
  const md = cryptoFramework.createMd('MD5');
  const encoder: util.TextEncoder = new util.TextEncoder();
  const data: Uint8Array = encoder.encodeInto(input);
  md.updateSync({ data: data });
  const digest = md.digestSync();
  return bytesToHex(digest.data);
}
