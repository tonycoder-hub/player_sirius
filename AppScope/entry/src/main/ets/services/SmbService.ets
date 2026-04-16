import type { common } from '@kit.AbilityKit';

export interface SmbCapability {
  available: boolean;
  backendName: string;
  blocker: string;
  features: string[];
  version?: string;
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

export interface SmbBridgeState {
  sessionState: string;
  profileName: string;
  host: string;
  port: number;
  share: string;
  username: string;
  path: string;
  lastError: string;
}

export interface SmbBridgeEvent extends SmbBridgeState {
  type: string;
  message: string;
}

type SmbBridgeEventListener = (event: SmbBridgeEvent) => void;

declare function requireNapi(name: string): SmbNativeBridge;

interface SmbNativeBridge {
  getCapability?: () => SmbCapability;
  getState?: () => SmbBridgeState;
  setEventListener?: (listener: SmbBridgeEventListener) => void;
  clearEventListener?: () => void;
  configureProfile?: (
    profileName: string,
    host: string,
    port: number,
    share: string,
    username: string,
    password: string,
    path: string
  ) => number;
  listDirectory?: () => Promise<SmbEntry[]> | SmbEntry[];
  openFile?: (path: string, cacheDir: string, suggestedName: string) => Promise<string> | string;
  release?: () => void;
}

const SMB_BLOCKER = '当前仓库尚未接入 libsmb2 Native 依赖，SMB/NAS 浏览暂不可用。';

export class SmbService {
  private bridge: SmbNativeBridge | null = null;
  private context: common.UIAbilityContext | null = null;

  constructor() {
    this.bridge = this.tryLoadBridge();
  }

  getCapability(): SmbCapability {
    return this.bridge?.getCapability?.() ?? {
      available: false,
      backendName: 'libsmb2-placeholder',
      blocker: SMB_BLOCKER,
      features: ['profile-storage', 'smb-uri-builder', 'native-dependency-slot'],
      version: 'stub'
    };
  }

  getState(): SmbBridgeState {
    return this.bridge?.getState?.() ?? {
      sessionState: 'unloaded',
      profileName: '',
      host: '',
      port: 445,
      share: '',
      username: '',
      path: '/',
      lastError: ''
    };
  }

  setEventListener(listener: SmbBridgeEventListener): void {
    this.bridge?.setEventListener?.(listener);
  }

  clearEventListener(): void {
    this.bridge?.clearEventListener?.();
  }

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
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
    const configured = this.bridge?.configureProfile?.(
      normalized.name,
      normalized.host,
      normalized.port,
      normalized.share,
      normalized.username,
      normalized.password,
      normalized.path
    ) ?? -1;
    if (configured !== 0) {
      throw new Error(this.getState().lastError || this.getCapability().blocker);
    }
    const result = this.bridge?.listDirectory?.();
    return await Promise.resolve(result ?? []);
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
    const configured = this.bridge?.configureProfile?.(
      normalized.name,
      normalized.host,
      normalized.port,
      normalized.share,
      normalized.username,
      normalized.password,
      normalized.path
    ) ?? -1;
    if (configured !== 0) {
      throw new Error(this.getState().lastError || this.getCapability().blocker);
    }
    const cacheDir = this.context?.cacheDir ?? this.context?.filesDir ?? '';
    if (cacheDir.length === 0) {
      throw new Error('无法获取应用缓存目录');
    }
    const maybeResult = this.bridge?.openFile?.(entry.path, cacheDir, entry.name);
    const result = await Promise.resolve(maybeResult ?? '');
    if (result.length === 0) {
      throw new Error(this.getState().lastError || this.getCapability().blocker);
    }
    return result;
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

  release(): void {
    this.bridge?.release?.();
  }

  private tryLoadBridge(): SmbNativeBridge | null {
    try {
      return requireNapi('smb_client_bridge');
    } catch (err) {
      console.warn(`SMB native bridge unavailable: ${err}`);
    }
    return null;
  }
}
