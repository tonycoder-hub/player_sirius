import { socket, connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';

interface LocalMediaEntry {
  uri: string;
  displayName: string;
  contentType: string;
  createdAt: number;
  lastAccessAt: number;
}

export class LocalMediaHttpServerService {
  private static readonly TOKEN_TTL_MS: number = 30 * 60 * 1000;
  private static readonly MAX_ENTRY_COUNT: number = 32;
  private server: socket.TCPSocketServer | null = null;
  private readonly portCandidates: number[] = [19081, 19082, 19083];
  private listenPort: number = 0;
  private listenHost: string = '';
  private readonly entries: Map<string, LocalMediaEntry> = new Map();

  async registerMedia(uri: string, displayName: string): Promise<string> {
    await this.ensureStarted();
    if (this.listenPort <= 0 || this.listenHost.length === 0) {
      return '';
    }
    const normalizedUri = this.normalizeReadableUri(uri);
    if (normalizedUri.length === 0) {
      return '';
    }
    this.cleanupExpiredEntries();
    const now = Date.now();
    const token = this.createAccessToken();
    this.entries.set(token, {
      uri: normalizedUri,
      displayName,
      contentType: this.getContentType(displayName),
      createdAt: now,
      lastAccessAt: now
    });
    this.trimEntries();
    return `http://${this.listenHost}:${this.listenPort}/media/${token}`;
  }

  async stop(): Promise<void> {
    if (!this.server) {
      return;
    }
    try {
      await this.server.close();
    } catch {
      // ignore
    }
    this.server = null;
    this.listenPort = 0;
    this.listenHost = '';
    this.entries.clear();
  }

  private async ensureStarted(): Promise<void> {
    if (this.server) {
      return;
    }

    this.listenHost = this.getLocalIpv4Address();
    if (this.listenHost.length === 0) {
      return;
    }

    const server = socket.constructTCPSocketServerInstance();
    server.on('connect', (client: socket.TCPSocketConnection) => {
      this.handleClient(client);
    });

    let started = false;
    for (const port of this.portCandidates) {
      try {
        await server.listen({ address: this.listenHost, port, family: 1 });
        this.listenPort = port;
        started = true;
        break;
      } catch {
        // try next port
      }
    }

    if (!started) {
      try {
        await server.close();
      } catch {
        // ignore
      }
      return;
    }

    this.server = server;
  }

  private async handleClient(client: socket.TCPSocketConnection): Promise<void> {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let requestBuffer = '';
    const onMessage = async (info: socket.SocketMessageInfo) => {
      try {
        requestBuffer += decoder.decodeToString(new Uint8Array(info.message), { stream: true });
        if (requestBuffer.length > 16 * 1024) {
          await this.sendTextResponse(client, 431, 'Request Header Fields Too Large', 'headers too large');
          return;
        }
        if (!requestBuffer.includes('\r\n\r\n') && !requestBuffer.includes('\n\n')) {
          return;
        }
        requestBuffer += decoder.decodeToString(new Uint8Array(), { stream: false });
        await this.handleHttpRequest(client, requestBuffer);
      } finally {
        if (requestBuffer.includes('\r\n\r\n') || requestBuffer.includes('\n\n') || requestBuffer.length > 16 * 1024) {
          client.off('message');
        }
      }
    };

    client.on('message', onMessage);
  }

  private async handleHttpRequest(client: socket.TCPSocketConnection, request: string): Promise<void> {
    const firstLine = request.split(/\r?\n/)[0] ?? '';
    const match = firstLine.match(/^(GET|HEAD)\s+([^\s]+)\s+HTTP\/1\.[01]$/i);
    if (!match) {
      await this.sendTextResponse(client, 400, 'Bad Request', 'invalid request');
      return;
    }

    const method = match[1].toUpperCase();
    const path = match[2];
    const mediaMatch = path.match(/^\/media\/([A-Za-z0-9_-]+)$/);
    if (!mediaMatch) {
      await this.sendTextResponse(client, 404, 'Not Found', 'not found');
      return;
    }

    const token = mediaMatch[1];
    this.cleanupExpiredEntries();
    const entry = this.entries.get(token);
    if (!entry) {
      await this.sendTextResponse(client, 404, 'Not Found', 'media expired');
      return;
    }
    if (Date.now() - entry.createdAt > LocalMediaHttpServerService.TOKEN_TTL_MS) {
      this.entries.delete(token);
      await this.sendTextResponse(client, 404, 'Not Found', 'media expired');
      return;
    }
    entry.lastAccessAt = Date.now();

    const rangeHeader = this.extractHeader(request, 'range');
    let start = 0;
    let end = -1;
    const stat = fs.statSync(entry.uri);
    const totalSize = Math.max(0, Number(stat.size ?? 0));
    if (totalSize <= 0) {
      await this.sendTextResponse(client, 404, 'Not Found', 'empty media');
      return;
    }
    end = totalSize - 1;

    let statusCode = 200;
    let statusText = 'OK';
    if (rangeHeader.length > 0) {
      const rangeMatch = rangeHeader.match(/bytes=(\d+)-(\d*)/i);
      if (rangeMatch) {
        start = Number(rangeMatch[1]);
        if (rangeMatch[2].length > 0) {
          end = Math.min(end, Number(rangeMatch[2]));
        }
        if (start > end || start >= totalSize) {
          await client.send({
            data:
              `HTTP/1.1 416 Range Not Satisfiable\r\n` +
              `Content-Range: bytes */${totalSize}\r\n` +
              `Connection: close\r\n\r\n`,
            encoding: 'utf-8'
          });
          await client.close();
          return;
        }
        statusCode = 206;
        statusText = 'Partial Content';
      }
    }

    const contentLength = end - start + 1;
    let headers =
      `HTTP/1.1 ${statusCode} ${statusText}\r\n` +
      `Content-Type: ${entry.contentType}\r\n` +
      `Accept-Ranges: bytes\r\n` +
      `Content-Length: ${contentLength}\r\n` +
      `Connection: close\r\n`;
    if (statusCode === 206) {
      headers += `Content-Range: bytes ${start}-${end}/${totalSize}\r\n`;
    }
    headers += `\r\n`;

    await client.send({ data: headers, encoding: 'utf-8' });
    if (method === 'HEAD') {
      await client.close();
      return;
    }

    const file = fs.openSync(entry.uri, fs.OpenMode.READ_ONLY);
    try {
      let offset = start;
      const chunkSize = 64 * 1024;
      while (offset <= end) {
        const length = Math.min(chunkSize, end - offset + 1);
        const buffer = new ArrayBuffer(length);
        const readLen = fs.readSync(file.fd, buffer, { offset, length });
        if (readLen <= 0) {
          break;
        }
        const payload = readLen === buffer.byteLength ? buffer : buffer.slice(0, readLen);
        await client.send({ data: payload });
        offset += readLen;
      }
    } finally {
      try {
        fs.closeSync(file);
      } catch {
        // ignore
      }
      await client.close().catch(() => {});
    }
  }

  private async sendTextResponse(
    client: socket.TCPSocketConnection,
    statusCode: number,
    statusText: string,
    body: string
  ): Promise<void> {
    const headers =
      `HTTP/1.1 ${statusCode} ${statusText}\r\n` +
      `Content-Type: text/plain; charset=utf-8\r\n` +
      `Content-Length: ${body.length}\r\n` +
      `Connection: close\r\n\r\n` +
      body;
    await client.send({ data: headers, encoding: 'utf-8' });
    await client.close().catch(() => {});
  }

  private extractHeader(request: string, headerName: string): string {
    const lines = request.split(/\r?\n/);
    const lowerName = `${headerName.toLowerCase()}:`;
    for (const line of lines) {
      if (line.toLowerCase().startsWith(lowerName)) {
        return line.slice(lowerName.length).trim();
      }
    }
    return '';
  }

  private getLocalIpv4Address(): string {
    try {
      const netHandle = connection.getDefaultNetSync();
      const properties = connection.getConnectionPropertiesSync(netHandle);
      const linkAddresses = properties.linkAddresses;
      for (const item of linkAddresses) {
        const address = item.address.address;
        if (/^\d+\.\d+\.\d+\.\d+$/.test(address) && address !== '127.0.0.1') {
          return address;
        }
      }
    } catch {
      // ignore
    }
    return '';
  }

  private getContentType(name: string): string {
    const lower = name.toLowerCase();
    if (lower.endsWith('.m3u8')) {
      return 'application/vnd.apple.mpegurl';
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mkv')) {
      return 'video/x-matroska';
    }
    if (lower.endsWith('.avi')) {
      return 'video/x-msvideo';
    }
    if (lower.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lower.endsWith('.flv')) {
      return 'video/x-flv';
    }
    return 'application/octet-stream';
  }

  private normalizeReadableUri(uri: string): string {
    const trimmed = uri.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      return decodeURIComponent(trimmed.slice('file://'.length));
    }
    return trimmed;
  }

  private createAccessToken(): string {
    return [
      Date.now().toString(36),
      Math.random().toString(36).slice(2, 10),
      Math.random().toString(36).slice(2, 10),
      Math.random().toString(36).slice(2, 10)
    ].join('');
  }

  private cleanupExpiredEntries(): void {
    const now = Date.now();
    const expiredTokens: string[] = [];
    this.entries.forEach((entry: LocalMediaEntry, token: string) => {
      if (now - entry.createdAt > LocalMediaHttpServerService.TOKEN_TTL_MS) {
        expiredTokens.push(token);
      }
    });
    expiredTokens.forEach((token: string) => this.entries.delete(token));
  }

  private trimEntries(): void {
    if (this.entries.size <= LocalMediaHttpServerService.MAX_ENTRY_COUNT) {
      return;
    }
    const sorted = Array.from(this.entries.entries())
      .sort((left: [string, LocalMediaEntry], right: [string, LocalMediaEntry]) => left[1].lastAccessAt - right[1].lastAccessAt);
    const removeCount = this.entries.size - LocalMediaHttpServerService.MAX_ENTRY_COUNT;
    for (let index = 0; index < removeCount; index++) {
      this.entries.delete(sorted[index][0]);
    }
  }
}
