import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import type { MediaItem } from '../model/MediaItem';

const PREFERENCES_NAME = 'player_sirius_prefs';
const KEY_HISTORY = 'play_history';
const KEY_LIBRARY = 'media_library';
const MAX_HISTORY_SIZE = 50;
const MAX_LIBRARY_SIZE = 200;

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
        throw error;
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
      fileSizeBytes: item.fileSizeBytes ?? 0
    };
  }

  private mergeMediaItem(current: MediaItem, incoming: MediaItem): MediaItem {
    return this.createDefaultMediaItem({
      ...current,
      ...incoming,
      id: current.id || incoming.id,
      uri: incoming.uri || current.uri,
      title: incoming.title || current.title,
      addedTime: current.addedTime || incoming.addedTime,
      isFavorite: incoming.isFavorite ?? current.isFavorite,
      lastPlayedAt: Math.max(current.lastPlayedAt ?? 0, incoming.lastPlayedAt ?? 0),
      playCount: Math.max(current.playCount ?? 0, incoming.playCount ?? 0),
      isCompleted: incoming.isCompleted ?? current.isCompleted
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
        ...item,
        lastPlayedAt: item.lastPlayedAt > 0 ? item.lastPlayedAt : Date.now()
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
