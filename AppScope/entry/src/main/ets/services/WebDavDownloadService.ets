import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';

export class WebDavDownloadService {
  static async downloadToCache(
    context: common.UIAbilityContext,
    fileUrl: string,
    suggestedName: string,
    username?: string,
    password?: string
  ): Promise<string> {
    const safeName = WebDavDownloadService.sanitizeFileName(suggestedName);
    const cacheDir = (context as unknown as { cacheDir?: string }).cacheDir ?? (context as unknown as { filesDir?: string }).filesDir ?? '';
    if (cacheDir.length === 0) {
      throw new Error('无法获取应用缓存目录');
    }

    const targetDir = `${cacheDir}/webdav_cache`;
    WebDavDownloadService.ensureDir(targetDir);

    const suffix = WebDavDownloadService.getExtensionFromName(safeName);
    const targetPath = `${targetDir}/${Date.now()}_${Math.random().toString(36).slice(2, 10)}${suffix}`;

    const headers: Record<string, string> = {};
    if (username && username.length > 0) {
      const token = WebDavDownloadService.base64Encode(`${username}:${password ?? ''}`);
      headers['Authorization'] = `Basic ${token}`;
    }

    let res: Response;
    try {
      res = await fetch(fileUrl, { method: 'GET', headers });
    } catch (err) {
      throw new Error('下载失败：网络请求异常');
    }

    if (!res.ok) {
      throw new Error(`下载失败：HTTP ${res.status}`);
    }

    const data = await res.arrayBuffer();
    if (data.byteLength <= 0) {
      throw new Error('下载失败：文件为空');
    }
    if (data.byteLength > 300 * 1024 * 1024) {
      throw new Error('下载失败：文件过大（>300MB），请改用直链或后续流式下载方案');
    }

    const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data);
    } catch (err) {
      const error = err as BusinessError;
      throw new Error(`写入缓存失败：${error.message ?? `${err}`}`);
    } finally {
      try {
        fs.closeSync(file);
      } catch {
        // ignore
      }
    }

    return `file://${targetPath}`;
  }

  private static ensureDir(path: string): void {
    try {
      fs.mkdirSync(path);
    } catch {
      // ignore (already exists or unsupported)
    }
  }

  private static sanitizeFileName(name: string): string {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return 'webdav_media';
    }
    // Replace path separators and control chars.
    return trimmed.replace(/[\\\/\u0000-\u001f]/g, '_').slice(0, 120);
  }

  private static getExtensionFromName(name: string): string {
    const idx = name.lastIndexOf('.');
    if (idx < 0 || idx === name.length - 1) {
      return '';
    }
    const ext = name.slice(idx).toLowerCase();
    if (ext.length > 12) {
      return '';
    }
    return ext;
  }

  private static base64Encode(value: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    const bytes = WebDavDownloadService.utf8Encode(value);
    let output = '';
    let i = 0;
    while (i < bytes.length) {
      const c1 = bytes[i++];
      const c2 = i < bytes.length ? bytes[i++] : Number.NaN;
      const c3 = i < bytes.length ? bytes[i++] : Number.NaN;

      const e1 = c1 >> 2;
      const e2 = ((c1 & 3) << 4) | (c2 >> 4);
      let e3 = ((c2 & 15) << 2) | (c3 >> 6);
      let e4 = c3 & 63;

      if (Number.isNaN(c2)) {
        e3 = 64;
        e4 = 64;
      } else if (Number.isNaN(c3)) {
        e4 = 64;
      }

      output += chars.charAt(e1) + chars.charAt(e2) + chars.charAt(e3) + chars.charAt(e4);
    }
    return output;
  }

  private static utf8Encode(value: string): number[] {
    const bytes: number[] = [];
    for (const char of value) {
      const codePoint = char.codePointAt(0) ?? 0;
      if (codePoint <= 0x7F) {
        bytes.push(codePoint);
      } else if (codePoint <= 0x7FF) {
        bytes.push(0xC0 | (codePoint >> 6));
        bytes.push(0x80 | (codePoint & 0x3F));
      } else if (codePoint <= 0xFFFF) {
        bytes.push(0xE0 | (codePoint >> 12));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
        bytes.push(0x80 | (codePoint & 0x3F));
      } else {
        bytes.push(0xF0 | (codePoint >> 18));
        bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
        bytes.push(0x80 | (codePoint & 0x3F));
      }
    }
    return bytes;
  }
}
