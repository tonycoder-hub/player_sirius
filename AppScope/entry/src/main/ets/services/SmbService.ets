export interface SmbCapability {
  available: boolean;
  backendName: string;
  blocker: string;
  features: string[];
}

export interface SmbConnectionProfile {
  id: string;
  name: string;
  host: string;
  port: number;
  share: string;
  username: string;
  password: string;
  path: string;
}

export interface SmbEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAt: number;
}

const SMB_BLOCKER = '当前仓库尚未接入 libsmb2 Native 依赖，SMB/NAS 浏览暂不可用。';

export class SmbService {
  getCapability(): SmbCapability {
    return {
      available: false,
      backendName: 'libsmb2-placeholder',
      blocker: SMB_BLOCKER,
      features: ['profile-storage', 'smb-uri-builder', 'native-dependency-slot']
    };
  }

  sanitizeProfile(profile: Partial<SmbConnectionProfile>): SmbConnectionProfile {
    return {
      id: profile.id ?? `${Date.now()}_${Math.random().toString(36).slice(2, 11)}`,
      name: profile.name?.trim() || profile.share?.trim() || profile.host?.trim() || 'SMB 连接',
      host: profile.host?.trim() || '',
      port: Number(profile.port) > 0 ? Number(profile.port) : 445,
      share: profile.share?.trim().replace(/^\/+|\/+$/g, '') || '',
      username: profile.username?.trim() || '',
      password: profile.password ?? '',
      path: this.normalizePath(profile.path || '/')
    };
  }

  validateProfile(profile: SmbConnectionProfile): string {
    if (profile.host.length === 0) {
      return '请输入 SMB 主机地址。';
    }
    if (profile.share.length === 0) {
      return '请输入共享名称。';
    }
    return '';
  }

  async listDirectory(profile: SmbConnectionProfile): Promise<SmbEntry[]> {
    const normalized = this.sanitizeProfile(profile);
    const validationError = this.validateProfile(normalized);
    if (validationError.length > 0) {
      throw new Error(validationError);
    }
    throw new Error(this.getCapability().blocker);
  }

  async openFile(profile: SmbConnectionProfile, entry: SmbEntry): Promise<string> {
    const normalized = this.sanitizeProfile(profile);
    const validationError = this.validateProfile(normalized);
    if (validationError.length > 0) {
      throw new Error(validationError);
    }
    if (entry.isDirectory) {
      throw new Error('目录不能直接播放，请先进入目录。');
    }
    throw new Error(this.getCapability().blocker);
  }

  buildSmbUri(profile: SmbConnectionProfile, targetPath?: string): string {
    const normalized = this.sanitizeProfile(profile);
    const path = this.normalizePath(targetPath ?? normalized.path);
    const auth = normalized.username.length > 0
      ? `${encodeURIComponent(normalized.username)}${normalized.password.length > 0 ? `:${encodeURIComponent(normalized.password)}` : ''}@`
      : '';
    const port = normalized.port !== 445 ? `:${normalized.port}` : '';
    return `smb://${auth}${normalized.host}${port}/${normalized.share}${path}`;
  }

  normalizePath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length === 0 || trimmed === '/') {
      return '/';
    }
    const normalized = trimmed.replace(/\\/g, '/');
    return normalized.startsWith('/') ? normalized : `/${normalized}`;
  }
}
