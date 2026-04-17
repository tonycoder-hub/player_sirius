import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import type { MediaItem } from '../model/MediaItem';
import type { SmbConnectionProfile } from './SmbService';

const PREFERENCES_NAME = 'player_sirius_prefs';
const KEY_HISTORY = 'play_history';
const KEY_LIBRARY = 'media_library';
const KEY_LIBRARY_ROOTS = 'media_library_roots';
const KEY_SMB_PROFILES = 'smb_profiles';
const KEY_SUBTITLE_BINDINGS = 'subtitle_bindings';
const MAX_HISTORY_SIZE = 50;
const MAX_LIBRARY_SIZE = 200;

export interface SubtitleBinding {
  mediaUri: string;
  subtitleUri: string;
  subtitleLabel: string;
  offsetSeconds: number;
  updatedAt: number;
}

export class StorageService {
  private context: Context | null = null;
  private prefs: preferences.Preferences | null = null;

  constructor() {}

  setContext(context: Context): void {
    this.context = context;
  }

  private async getPreferences(): Promise<preferences.Preferences> {
    if (!this.prefs && this.context) {
      try {
        this.prefs = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      } catch (err) {
        const error = err as BusinessError;
        console.error(`Get preferences failed: ${error.code}, ${error.message}`);
        throw new Error(error.message);
      }
    }
    if (!this.prefs) {
      throw new Error('Preferences not initialized');
    }
    return this.prefs;
  }

  private createDefaultMediaItem(item: Partial<MediaItem>): MediaItem {
    return {
      id: item.id ?? `${Date.now()}_${Math.random().toString(36).slice(2, 11)}`,
      uri: item.uri ?? '',
      title: item.title ?? '未知视频',
      duration: item.duration ?? 0,
      lastPosition: item.lastPosition ?? 0,
      addedTime: item.addedTime ?? Date.now(),
      sourceType: item.sourceType ?? 'local',
      folderName: item.folderName ?? '根目录',
      isFavorite: item.isFavorite ?? false,
      lastPlayedAt: item.lastPlayedAt ?? item.addedTime ?? Date.now(),
      playCount: item.playCount ?? 0,
      isCompleted: item.isCompleted ?? false,
      thumbnailUri: item.thumbnailUri ?? '',
      width: item.width ?? 0,
      height: item.height ?? 0,
      fileSizeBytes: item.fileSizeBytes ?? 0,
      importRootUri: item.importRootUri ?? ''
    };
  }

  private mergeMediaItem(current: MediaItem, incoming: MediaItem): MediaItem {
    return this.createDefaultMediaItem({
      id: current.id || incoming.id,
      uri: incoming.uri || current.uri,
      title: incoming.title || current.title,
      duration: incoming.duration || current.duration,
      lastPosition: incoming.lastPosition || current.lastPosition,
      addedTime: current.addedTime || incoming.addedTime,
      sourceType: incoming.sourceType || current.sourceType,
      folderName: incoming.folderName || current.folderName,
      isFavorite: incoming.isFavorite ?? current.isFavorite,
      lastPlayedAt: Math.max(current.lastPlayedAt ?? 0, incoming.lastPlayedAt ?? 0),
      playCount: Math.max(current.playCount ?? 0, incoming.playCount ?? 0),
      isCompleted: incoming.isCompleted ?? current.isCompleted,
      thumbnailUri: incoming.thumbnailUri || current.thumbnailUri,
      width: incoming.width || current.width,
      height: incoming.height || current.height,
      fileSizeBytes: incoming.fileSizeBytes || current.fileSizeBytes,
      importRootUri: incoming.importRootUri || current.importRootUri
    });
  }

  private async readItems(key: string): Promise<MediaItem[]> {
    const prefs = await this.getPreferences();
    try {
      const rawValue = await prefs.get(key, '[]');
      const parsed = JSON.parse(rawValue as string) as Partial<MediaItem>[];
      return parsed
        .map((item: Partial<MediaItem>) => this.createDefaultMediaItem(item))
        .filter((item: MediaItem) => item.uri.length > 0);
    } catch {
      return [];
    }
  }

  private async writeItems(key: string, items: MediaItem[]): Promise<void> {
    const prefs = await this.getPreferences();
    await prefs.put(key, JSON.stringify(items));
    await prefs.flush();
  }

  private async readStringArray(key: string): Promise<string[]> {
    const prefs = await this.getPreferences();
    try {
      const rawValue = await prefs.get(key, '[]');
      const parsed = JSON.parse(rawValue as string) as string[];
      return parsed.filter((item: string) => item.length > 0);
    } catch {
      return [];
    }
  }

  private async writeStringArray(key: string, values: string[]): Promise<void> {
    const prefs = await this.getPreferences();
    await prefs.put(key, JSON.stringify(values));
    await prefs.flush();
  }

  private createDefaultSubtitleBinding(binding: Partial<SubtitleBinding>): SubtitleBinding {
    return {
      mediaUri: binding.mediaUri ?? '',
      subtitleUri: binding.subtitleUri ?? '',
      subtitleLabel: binding.subtitleLabel ?? '',
      offsetSeconds: Number(binding.offsetSeconds ?? 0),
      updatedAt: Number(binding.updatedAt ?? Date.now())
    };
  }

  private createDefaultSmbProfile(profile: Partial<SmbConnectionProfile>): SmbConnectionProfile {
    return {
      id: profile.id ?? `${Date.now()}_${Math.random().toString(36).slice(2, 11)}`,
      name: profile.name?.trim() || profile.share?.trim() || profile.host?.trim() || 'SMB 连接',
      host: profile.host?.trim() || '',
      port: Number(profile.port) > 0 ? Number(profile.port) : 445,
      share: profile.share?.trim() || '',
      username: profile.username?.trim() || '',
      password: profile.password ?? '',
      path: profile.path?.trim() || '/'
    };
  }

  private createPersistableSmbProfile(profile: SmbConnectionProfile): SmbConnectionProfile {
    return {
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      share: profile.share,
      username: profile.username,
      password: '',
      path: profile.path
    };
  }

  private toStatableLocalPath(uri: string): string | null {
    if (uri.startsWith('/')) {
      return uri;
    }
    if (uri.startsWith('file:///')) {
      return decodeURIComponent(uri.slice('file://'.length));
    }
    return null;
  }

  private upsertItems(items: MediaItem[], incoming: MediaItem, sortByLastPlayed: boolean): MediaItem[] {
    const nextItems = [...items];
    const existingIndex = nextItems.findIndex((item: MediaItem) => item.uri === incoming.uri);
    if (existingIndex >= 0) {
      nextItems[existingIndex] = this.mergeMediaItem(nextItems[existingIndex], incoming);
    } else {
      nextItems.push(this.createDefaultMediaItem(incoming));
    }

    nextItems.sort((left: MediaItem, right: MediaItem) => {
      if (sortByLastPlayed) {
        return (right.lastPlayedAt ?? 0) - (left.lastPlayedAt ?? 0);
      }
      return (right.addedTime ?? 0) - (left.addedTime ?? 0);
    });
    return nextItems;
  }

  async upsertMediaItem(item: MediaItem): Promise<void> {
    try {
      const library = await this.readItems(KEY_LIBRARY);
      const mergedLibrary = this.upsertItems(library, item, false).slice(0, MAX_LIBRARY_SIZE);
      await this.writeItems(KEY_LIBRARY, mergedLibrary);
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Upsert media item failed: ${message}`);
    }
  }

  async saveMediaLibraryItems(items: MediaItem[]): Promise<void> {
    try {
      let library = await this.readItems(KEY_LIBRARY);
      items.forEach((item: MediaItem) => {
        library = this.upsertItems(library, item, false);
      });
      await this.writeItems(KEY_LIBRARY, library.slice(0, MAX_LIBRARY_SIZE));
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Save media library failed: ${message}`);
    }
  }

  async getMediaLibrary(): Promise<MediaItem[]> {
    try {
      return await this.readItems(KEY_LIBRARY);
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Get media library failed: ${message}`);
      return [];
    }
  }

  async saveLibraryImportRoot(rootUri: string): Promise<void> {
    if (rootUri.trim().length === 0) {
      return;
    }
    const roots = await this.getLibraryImportRoots();
    if (roots.includes(rootUri)) {
      return;
    }
    roots.push(rootUri);
    await this.writeStringArray(KEY_LIBRARY_ROOTS, roots);
  }

  async getLibraryImportRoots(): Promise<string[]> {
    try {
      return await this.readStringArray(KEY_LIBRARY_ROOTS);
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Get library roots failed: ${message}`);
      return [];
    }
  }

  async pruneLibraryItems(itemsToKeep: MediaItem[]): Promise<void> {
    try {
      await this.writeItems(KEY_LIBRARY, itemsToKeep.slice(0, MAX_LIBRARY_SIZE));
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Prune media library failed: ${message}`);
    }
  }

  async pruneLibraryItemsByTrackedRoots(trackedRoots: string[], knownUris: string[]): Promise<number> {
    try {
      const known = new Set<string>(knownUris);
      const roots = trackedRoots.filter((root: string) => root.length > 0);
      const library = await this.readItems(KEY_LIBRARY);
      const filtered = library.filter((item: MediaItem) => {
        if (item.sourceType !== 'local') {
          return true;
        }
        if (!item.importRootUri || !roots.includes(item.importRootUri)) {
          return true;
        }
        return known.has(item.uri);
      });
      const removedCount = library.length - filtered.length;
      if (removedCount > 0) {
        await this.writeItems(KEY_LIBRARY, filtered);
      }
      return removedCount;
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Prune tracked roots failed: ${message}`);
      return 0;
    }
  }

  async cleanupMissingLocalMedia(): Promise<number> {
    try {
      const library = await this.readItems(KEY_LIBRARY);
      const filtered = library.filter((item: MediaItem) => {
        if (item.sourceType !== 'local') {
          return true;
        }
        const statablePath = this.toStatableLocalPath(item.uri);
        if (!statablePath) {
          return true;
        }
        try {
          fs.statSync(statablePath);
          return true;
        } catch {
          return false;
        }
      });
      const removedCount = library.length - filtered.length;
      if (removedCount > 0) {
        await this.writeItems(KEY_LIBRARY, filtered);
      }
      return removedCount;
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Cleanup media library failed: ${message}`);
      return 0;
    }
  }

  async getSmbProfiles(): Promise<SmbConnectionProfile[]> {
    try {
      const prefs = await this.getPreferences();
      const rawValue = await prefs.get(KEY_SMB_PROFILES, '[]');
      const parsed = JSON.parse(rawValue as string) as Partial<SmbConnectionProfile>[];
      return parsed.map((profile: Partial<SmbConnectionProfile>) =>
        this.createPersistableSmbProfile(this.createDefaultSmbProfile(profile))
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Get SMB profiles failed: ${message}`);
      return [];
    }
  }

  async saveSmbProfile(profile: SmbConnectionProfile): Promise<void> {
    try {
      const existing = await this.getSmbProfiles();
      const next = [...existing];
      const normalized = this.createPersistableSmbProfile(this.createDefaultSmbProfile(profile));
      const index = next.findIndex((item: SmbConnectionProfile) => item.id === normalized.id);
      if (index >= 0) {
        next[index] = normalized;
      } else {
        next.unshift(normalized);
      }
      const persistable = next.map((item: SmbConnectionProfile) => this.createPersistableSmbProfile(item));
      const prefs = await this.getPreferences();
      await prefs.put(KEY_SMB_PROFILES, JSON.stringify(persistable.slice(0, 10)));
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Save SMB profile failed: ${message}`);
    }
  }

  async deleteSmbProfile(profileId: string): Promise<void> {
    try {
      const next = (await this.getSmbProfiles()).filter((profile: SmbConnectionProfile) => profile.id !== profileId);
      const prefs = await this.getPreferences();
      await prefs.put(KEY_SMB_PROFILES, JSON.stringify(next));
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Delete SMB profile failed: ${message}`);
    }
  }

  async saveSubtitleBinding(binding: SubtitleBinding): Promise<void> {
    if (binding.mediaUri.trim().length === 0 || binding.subtitleUri.trim().length === 0) {
      return;
    }
    try {
      const prefs = await this.getPreferences();
      const rawValue = await prefs.get(KEY_SUBTITLE_BINDINGS, '[]');
      const parsed = JSON.parse(rawValue as string) as Partial<SubtitleBinding>[];
      const normalized = this.createDefaultSubtitleBinding({
        mediaUri: binding.mediaUri,
        subtitleUri: binding.subtitleUri,
        subtitleLabel: binding.subtitleLabel,
        offsetSeconds: binding.offsetSeconds,
        updatedAt: Date.now()
      });
      const next = parsed
        .map((item: Partial<SubtitleBinding>) => this.createDefaultSubtitleBinding(item))
        .filter((item: SubtitleBinding) => item.mediaUri.length > 0 && item.mediaUri !== normalized.mediaUri);
      next.unshift(normalized);
      await prefs.put(KEY_SUBTITLE_BINDINGS, JSON.stringify(next.slice(0, 200)));
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Save subtitle binding failed: ${message}`);
    }
  }

  async getSubtitleBinding(mediaUri: string): Promise<SubtitleBinding | null> {
    if (mediaUri.trim().length === 0) {
      return null;
    }
    try {
      const prefs = await this.getPreferences();
      const rawValue = await prefs.get(KEY_SUBTITLE_BINDINGS, '[]');
      const parsed = JSON.parse(rawValue as string) as Partial<SubtitleBinding>[];
      const bindings = parsed.map((item: Partial<SubtitleBinding>) => this.createDefaultSubtitleBinding(item));
      return bindings.find((item: SubtitleBinding) => item.mediaUri === mediaUri && item.subtitleUri.length > 0) ?? null;
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Get subtitle binding failed: ${message}`);
      return null;
    }
  }

  async deleteSubtitleBinding(mediaUri: string): Promise<void> {
    if (mediaUri.trim().length === 0) {
      return;
    }
    try {
      const prefs = await this.getPreferences();
      const rawValue = await prefs.get(KEY_SUBTITLE_BINDINGS, '[]');
      const parsed = JSON.parse(rawValue as string) as Partial<SubtitleBinding>[];
      const next = parsed
        .map((item: Partial<SubtitleBinding>) => this.createDefaultSubtitleBinding(item))
        .filter((item: SubtitleBinding) => item.mediaUri.length > 0 && item.mediaUri !== mediaUri);
      await prefs.put(KEY_SUBTITLE_BINDINGS, JSON.stringify(next));
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Delete subtitle binding failed: ${message}`);
    }
  }

  async toggleFavorite(uri: string): Promise<boolean> {
    try {
      const library = await this.readItems(KEY_LIBRARY);
      const existingIndex = library.findIndex((item: MediaItem) => item.uri === uri);
      if (existingIndex < 0) {
        return false;
      }

      library[existingIndex].isFavorite = !library[existingIndex].isFavorite;
      await this.writeItems(KEY_LIBRARY, library);
      return library[existingIndex].isFavorite;
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Toggle favorite failed: ${message}`);
      return false;
    }
  }

  async getFavorites(): Promise<MediaItem[]> {
    const library = await this.getMediaLibrary();
    return library.filter((item: MediaItem) => item.isFavorite);
  }

  async savePlayHistory(item: MediaItem): Promise<void> {
    try {
      const nextItem = this.createDefaultMediaItem({
        id: item.id,
        uri: item.uri,
        title: item.title,
        duration: item.duration,
        lastPosition: item.lastPosition,
        addedTime: item.addedTime,
        sourceType: item.sourceType,
        folderName: item.folderName,
        isFavorite: item.isFavorite,
        lastPlayedAt: item.lastPlayedAt > 0 ? item.lastPlayedAt : Date.now(),
        playCount: item.playCount,
        isCompleted: item.isCompleted,
        thumbnailUri: item.thumbnailUri,
        width: item.width,
        height: item.height,
        fileSizeBytes: item.fileSizeBytes,
        importRootUri: item.importRootUri
      });
      const history = await this.readItems(KEY_HISTORY);
      const mergedHistory = this.upsertItems(history, nextItem, true).slice(0, MAX_HISTORY_SIZE);
      await this.writeItems(KEY_HISTORY, mergedHistory);
      await this.upsertMediaItem(nextItem);
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Save play history failed: ${message}`);
    }
  }

  async getPlayHistory(): Promise<MediaItem[]> {
    try {
      return await this.readItems(KEY_HISTORY);
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Get play history failed: ${message}`);
      return [];
    }
  }

  async clearPlayHistory(): Promise<void> {
    try {
      const prefs = await this.getPreferences();
      await prefs.delete(KEY_HISTORY);
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Clear play history failed: ${message}`);
    }
  }
}
