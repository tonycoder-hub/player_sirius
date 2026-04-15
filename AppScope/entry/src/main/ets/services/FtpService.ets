import { BusinessError } from '@kit.BasicServicesKit';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';

export interface FtpEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  sizeBytes: number;
}

interface FtpReply {
  code: number;
  message: string;
}

export class FtpService {
  static async listDirectory(
    host: string,
    port: number,
    username: string,
    password: string,
    path: string
  ): Promise<FtpEntry[]> {
    const client = new FtpClient(host, port);
    try {
      await client.connect();
      await client.login(username, password);
      await client.typeBinary();

      // Prefer MLSD when available, fallback to LIST.
      const mlsd = await client.tryListMlsd(path);
      const entries = mlsd ?? await client.listList(path);

      entries.sort((a: FtpEntry, b: FtpEntry) => {
        if (a.isDirectory !== b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.localeCompare(b.name);
      });
      return entries;
    } finally {
      await client.close();
    }
  }

  static async downloadToCache(
    context: common.UIAbilityContext,
    host: string,
    port: number,
    username: string,
    password: string,
    remotePath: string,
    suggestedName: string
  ): Promise<string> {
    const cacheDir = (context as unknown as { cacheDir?: string }).cacheDir ?? (context as unknown as { filesDir?: string }).filesDir ?? '';
    if (cacheDir.length === 0) {
      throw new Error('无法获取应用缓存目录');
    }
    const targetDir = `${cacheDir}/ftp_cache`;
    try {
      fs.mkdirSync(targetDir);
    } catch {
      // ignore
    }

    const safeName = FtpService.sanitizeFileName(suggestedName);
    const suffix = FtpService.getExtensionFromName(safeName);
    const targetPath = `${targetDir}/${Date.now()}_${Math.random().toString(36).slice(2, 10)}${suffix}`;

    const client = new FtpClient(host, port);
    try {
      await client.connect();
      await client.login(username, password);
      await client.typeBinary();
      await client.retrToFile(remotePath, targetPath);
      return `file://${targetPath}`;
    } finally {
      await client.close();
    }
  }

  private static sanitizeFileName(name: string): string {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return 'ftp_media';
    }
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
}

class FtpClient {
  private readonly host: string;
  private readonly port: number;
  private tcp: socket.TCPSocket | null = null;
  private recvText: string = '';
  private currentReply: {
    resolve: (r: FtpReply) => void;
    reject: (e: Error) => void;
  } | null = null;

  private multilineCode: number | null = null;
  private multilineLines: string[] = [];

  constructor(host: string, port: number) {
    this.host = host;
    this.port = port;
  }

  async connect(): Promise<void> {
    this.tcp = socket.constructTCPSocketInstance();
    await this.tcp.bind({ address: '0.0.0.0', port: 0, family: 1 });

    this.tcp.on('message', (info: socket.SocketMessageInfo) => {
      this.onControlMessage(info.message);
    });

    await this.tcp.connect({
      address: { address: this.host, port: this.port, family: 1 },
      timeout: 8000
    });

    const greeting = await this.waitReply();
    if (greeting.code !== 220) {
      throw new Error(`FTP 连接失败：${greeting.code} ${greeting.message}`);
    }
  }

  async login(username: string, password: string): Promise<void> {
    const user = username.trim().length > 0 ? username.trim() : 'anonymous';
    const pass = username.trim().length > 0 ? password : 'anonymous@';

    const userReply = await this.command(`USER ${user}`);
    if (userReply.code === 230) {
      return;
    }
    if (userReply.code !== 331) {
      throw new Error(`FTP USER 失败：${userReply.code} ${userReply.message}`);
    }

    const passReply = await this.command(`PASS ${pass}`);
    if (passReply.code !== 230) {
      throw new Error(`FTP PASS 失败：${passReply.code} ${passReply.message}`);
    }
  }

  async typeBinary(): Promise<void> {
    const reply = await this.command('TYPE I');
    if (reply.code !== 200) {
      // Some servers return 250 for TYPE.
      if (reply.code !== 250) {
        throw new Error(`FTP TYPE 失败：${reply.code} ${reply.message}`);
      }
    }
  }

  async tryListMlsd(path: string): Promise<FtpEntry[] | null> {
    // Some servers require OPTS MLST; ignore failures.
    await this.command('OPTS MLST type;size;modify;').catch(() => {});
    const data = await this.dataCommandToText(`MLSD ${this.normalizePath(path)}`).catch(() => null);
    if (data === null) {
      return null;
    }
    return this.parseMlsd(data, path);
  }

  async listList(path: string): Promise<FtpEntry[]> {
    const data = await this.dataCommandToText(`LIST ${this.normalizePath(path)}`);
    return this.parseList(data, path);
  }

  async retrToFile(remotePath: string, localPath: string): Promise<void> {
    const pasv = await this.enterPassiveMode();
    const dataSocket = await this.openDataSocket(pasv.host, pasv.port);

    let offset = 0;
    const file = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);

    try {
      const done = new Promise<void>((resolve) => {
        dataSocket.on('close', () => resolve());
      });
      dataSocket.on('message', (info: socket.SocketMessageInfo) => {
        const chunk = info.message;
        if (chunk.byteLength <= 0) {
          return;
        }
        fs.writeSync(file.fd, chunk, { offset });
        offset += chunk.byteLength;
      });

      const first = await this.command(`RETR ${this.normalizePath(remotePath)}`);
      if (first.code !== 150 && first.code !== 125) {
        throw new Error(`FTP RETR 失败：${first.code} ${first.message}`);
      }

      await done;
      const final = await this.waitReply();
      if (final.code !== 226 && final.code !== 250) {
        throw new Error(`FTP 下载完成异常：${final.code} ${final.message}`);
      }
    } catch (err) {
      const error = err as BusinessError;
      const message = error?.message ?? `${err}`;
      throw new Error(message);
    } finally {
      try {
        fs.closeSync(file);
      } catch {
        // ignore
      }
      try {
        await dataSocket.close();
      } catch {
        // ignore
      }
    }
  }

  async close(): Promise<void> {
    if (!this.tcp) {
      return;
    }
    try {
      await this.command('QUIT').catch(() => {});
    } finally {
      try {
        await this.tcp.close();
      } catch {
        // ignore
      }
      this.tcp = null;
    }
  }

  private normalizePath(path: string): string {
    const p = path.trim();
    if (p.length === 0) {
      return '/';
    }
    return p;
  }

  private async command(cmd: string): Promise<FtpReply> {
    if (!this.tcp) {
      throw new Error('FTP 未连接');
    }
    const data = `${cmd}\r\n`;
    await this.tcp.send({ data, encoding: 'utf-8' });
    return await this.waitReply();
  }

  private waitReply(): Promise<FtpReply> {
    if (this.currentReply) {
      // This client is sequential; overlapping commands are a bug.
      return Promise.reject(new Error('FTP 命令并发执行未支持'));
    }
    return new Promise<FtpReply>((resolve, reject) => {
      this.currentReply = { resolve, reject };
    });
  }

  private onControlMessage(buffer: ArrayBuffer): void {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    const text = decoder.decodeToString(new Uint8Array(buffer), { stream: false });
    this.recvText += text;

    // Process complete lines.
    while (true) {
      const idx = this.recvText.indexOf('\r\n');
      if (idx < 0) {
        break;
      }
      const line = this.recvText.slice(0, idx);
      this.recvText = this.recvText.slice(idx + 2);
      this.onControlLine(line);
    }
  }

  private onControlLine(line: string): void {
    const trimmed = line.trimEnd();
    const m = trimmed.match(/^(\d{3})([\s-])(.*)$/);
    if (!m) {
      return;
    }

    const code = Number(m[1]);
    const sep = m[2];
    const msg = m[3] ?? '';

    if (sep === '-') {
      // Multiline start.
      this.multilineCode = code;
      this.multilineLines = [msg];
      return;
    }

    if (this.multilineCode !== null) {
      // Multiline end is "XYZ " where XYZ equals start code.
      if (code === this.multilineCode) {
        this.multilineLines.push(msg);
        const full = this.multilineLines.join('\n');
        this.multilineCode = null;
        this.multilineLines = [];
        this.resolveReply({ code, message: full });
      } else {
        this.multilineLines.push(msg);
      }
      return;
    }

    this.resolveReply({ code, message: msg });
  }

  private resolveReply(reply: FtpReply): void {
    if (!this.currentReply) {
      return;
    }
    const { resolve } = this.currentReply;
    this.currentReply = null;
    resolve(reply);
  }

  private async enterPassiveMode(): Promise<{ host: string; port: number }> {
    const reply = await this.command('PASV');
    if (reply.code !== 227) {
      throw new Error(`FTP PASV 失败：${reply.code} ${reply.message}`);
    }
    const match = reply.message.match(/\((\d+,\d+,\d+,\d+,\d+,\d+)\)/);
    if (!match) {
      throw new Error('FTP PASV 返回无法解析');
    }
    const parts = match[1].split(',').map((v: string) => Number(v));
    if (parts.length !== 6 || parts.some((v: number) => !Number.isFinite(v))) {
      throw new Error('FTP PASV 返回无法解析');
    }
    const host = `${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}`;
    const port = parts[4] * 256 + parts[5];
    return { host, port };
  }

  private async openDataSocket(host: string, port: number): Promise<socket.TCPSocket> {
    const tcp = socket.constructTCPSocketInstance();
    await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 });
    await tcp.connect({ address: { address: host, port, family: 1 }, timeout: 8000 });
    return tcp;
  }

  private async dataCommandToText(cmd: string): Promise<string> {
    const pasv = await this.enterPassiveMode();
    const dataSocket = await this.openDataSocket(pasv.host, pasv.port);
    let data = '';
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

    const done = new Promise<void>((resolve) => {
      dataSocket.on('close', () => resolve());
    });
    dataSocket.on('message', (info: socket.SocketMessageInfo) => {
      data += decoder.decodeToString(new Uint8Array(info.message), { stream: false });
    });

    const first = await this.command(cmd);
    if (first.code !== 150 && first.code !== 125) {
      await dataSocket.close().catch(() => {});
      throw new Error(`FTP 数据命令失败：${first.code} ${first.message}`);
    }

    await done;
    await dataSocket.close().catch(() => {});
    const final = await this.waitReply();
    if (final.code !== 226 && final.code !== 250) {
      throw new Error(`FTP 数据命令完成异常：${final.code} ${final.message}`);
    }

    return data;
  }

  private parseMlsd(text: string, basePath: string): FtpEntry[] {
    const entries: FtpEntry[] = [];
    const lines = text.split(/\r?\n/).map((l: string) => l.trim()).filter(Boolean);
    for (const line of lines) {
      // Example: type=file;size=123;modify=20200101000000; filename
      const idx = line.lastIndexOf(' ');
      if (idx <= 0) {
        continue;
      }
      const facts = line.slice(0, idx);
      const name = line.slice(idx + 1).trim();
      if (name === '.' || name === '..') {
        continue;
      }
      const typeMatch = facts.match(/type=([^;]+);/i);
      const sizeMatch = facts.match(/size=([0-9]+);/i);
      const type = (typeMatch?.[1] ?? '').toLowerCase();
      const isDirectory = type === 'dir' || type === 'cdir' || type === 'pdir';
      const sizeBytes = sizeMatch ? Number(sizeMatch[1]) : 0;
      const path = this.joinPath(basePath, name, isDirectory);
      // Skip current/parent dir markers if server returns them.
      if (type === 'cdir' || type === 'pdir') {
        continue;
      }
      entries.push({ name, path, isDirectory, sizeBytes: Number.isFinite(sizeBytes) ? sizeBytes : 0 });
    }
    return entries;
  }

  private parseList(text: string, basePath: string): FtpEntry[] {
    const entries: FtpEntry[] = [];
    const lines = text.split(/\r?\n/).map((l: string) => l.trim()).filter(Boolean);
    for (const line of lines) {
      // Best-effort Unix LIST parsing.
      // drwxr-xr-x  2 user group     4096 Jan 01 00:00 dirname
      // -rw-r--r--  1 user group   123456 Jan 01 00:00 file.mp4
      const tokens = line.split(/\s+/);
      if (tokens.length < 9) {
        continue;
      }
      const perms = tokens[0];
      const isDirectory = perms.startsWith('d');
      const sizeBytes = Number(tokens[4]) || 0;
      const name = tokens.slice(8).join(' ');
      if (name === '.' || name === '..') {
        continue;
      }
      const path = this.joinPath(basePath, name, isDirectory);
      entries.push({ name, path, isDirectory, sizeBytes });
    }
    return entries;
  }

  private joinPath(basePath: string, name: string, isDirectory: boolean): string {
    const base = basePath.trim().length > 0 ? basePath.trim() : '/';
    const normalizedBase = base.endsWith('/') ? base.slice(0, -1) : base;
    const joined = `${normalizedBase}/${name}`;
    return isDirectory ? `${joined}/` : joined;
  }
}

