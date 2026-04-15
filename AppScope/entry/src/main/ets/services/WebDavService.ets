export interface WebDavEntry {
  href: string;
  name: string;
  isDirectory: boolean;
  sizeBytes: number;
}

export class WebDavService {
  static async listDirectory(baseUrl: string, path: string, username?: string, password?: string): Promise<WebDavEntry[]> {
    const normalizedBase = baseUrl.trim().replace(/\/+$/, '');
    const normalizedPath = WebDavService.normalizePath(path);
    const url = `${normalizedBase}${normalizedPath}`;

    const headers: Record<string, string> = {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8'
    };
    if (username && username.length > 0) {
      const token = WebDavService.base64Encode(`${username}:${password ?? ''}`);
      headers['Authorization'] = `Basic ${token}`;
    }

    const body =
      `<?xml version="1.0" encoding="utf-8" ?>` +
      `<d:propfind xmlns:d="DAV:">` +
      `<d:prop>` +
      `<d:displayname/>` +
      `<d:getcontentlength/>` +
      `<d:resourcetype/>` +
      `</d:prop>` +
      `</d:propfind>`;

    const res = await fetch(url, {
      method: 'PROPFIND',
      headers,
      body
    });

    if (!res.ok) {
      throw new Error(`WebDAV 列目录失败：HTTP ${res.status}`);
    }

    const xml = await res.text();
    const entries = WebDavService.parseMultiStatus(xml, url);

    // Exclude the directory itself if present.
    const selfHrefCandidates = new Set<string>([
      normalizedPath,
      normalizedPath.endsWith('/') ? normalizedPath : `${normalizedPath}/`
    ]);

    const filtered = entries.filter((e: WebDavEntry) => {
      try {
        const u = new URL(e.href);
        return !selfHrefCandidates.has(u.pathname);
      } catch {
        return true;
      }
    });

    filtered.sort((a: WebDavEntry, b: WebDavEntry) => {
      if (a.isDirectory !== b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });
    return filtered;
  }

  private static normalizePath(path: string): string {
    const p = path.trim();
    if (p.length === 0 || p === '/') {
      return '/';
    }
    return p.startsWith('/') ? p : `/${p}`;
  }

  private static parseMultiStatus(xml: string, requestUrl: string): WebDavEntry[] {
    // Lightweight XML parsing via regex; good enough for typical WebDAV multistatus payloads.
    const responses = xml.split(/<d:response[\s>]/i).slice(1).map((chunk: string) => `<d:response ${chunk}`);
    const entries: WebDavEntry[] = [];
    for (const resp of responses) {
      const href = WebDavService.extractTag(resp, 'd:href') || WebDavService.extractTag(resp, 'D:href');
      if (!href) {
        continue;
      }
      const displayName = WebDavService.extractTag(resp, 'd:displayname') || WebDavService.extractTag(resp, 'D:displayname') || '';
      const sizeRaw = WebDavService.extractTag(resp, 'd:getcontentlength') || WebDavService.extractTag(resp, 'D:getcontentlength') || '0';
      const sizeBytes = Number(sizeRaw) || 0;

      const isCollection = /<d:collection\s*\/?>/i.test(resp) || /<D:collection\s*\/?>/i.test(resp);
      const absoluteHref = WebDavService.toAbsoluteHref(href, requestUrl);
      const name = displayName.trim().length > 0 ? displayName.trim() : WebDavService.basenameFromHref(absoluteHref);
      entries.push({
        href: absoluteHref,
        name,
        isDirectory: isCollection || absoluteHref.endsWith('/'),
        sizeBytes
      });
    }
    return entries;
  }

  private static extractTag(xml: string, tag: string): string | null {
    const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const match = xml.match(re);
    if (!match) {
      return null;
    }
    return WebDavService.decodeXmlEntities(match[1].trim());
  }

  private static decodeXmlEntities(value: string): string {
    return value
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
  }

  private static toAbsoluteHref(href: string, requestUrl: string): string {
    try {
      return new URL(href, requestUrl).toString();
    } catch {
      return href;
    }
  }

  private static basenameFromHref(href: string): string {
    try {
      const u = new URL(href);
      const path = u.pathname.endsWith('/') ? u.pathname.slice(0, -1) : u.pathname;
      const segments = path.split('/').filter(Boolean);
      return segments.length > 0 ? decodeURIComponent(segments[segments.length - 1]) : href;
    } catch {
      const trimmed = href.endsWith('/') ? href.slice(0, -1) : href;
      const parts = trimmed.split('/');
      return parts.length > 0 ? parts[parts.length - 1] : href;
    }
  }

  private static base64Encode(value: string): string {
    // ArkTS may not have btoa; use a small Base64 implementation for ASCII auth.
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    let i = 0;
    while (i < value.length) {
      const c1 = value.charCodeAt(i++);
      const c2 = value.charCodeAt(i++);
      const c3 = value.charCodeAt(i++);

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
}

