export interface MediaItem {
  id: string;
  uri: string;
  title: string;
  duration: number;
  lastPosition: number;
  addedTime: number;
  sourceType: string;
  folderName: string;
  isFavorite: boolean;
  lastPlayedAt: number;
  playCount: number;
  isCompleted: boolean;
  thumbnailUri?: string;
  width?: number;
  height?: number;
  fileSizeBytes?: number;
  importRootUri?: string;
}

export class MediaItemHelper {
  static create(uri: string, title: string = '未知视频'): MediaItem {
    return {
      id: MediaItemHelper.generateId(),
      uri,
      title,
      duration: 0,
      lastPosition: 0,
      addedTime: Date.now(),
      sourceType: MediaItemHelper.isNetworkUri(uri) ? 'network' : 'local',
      folderName: MediaItemHelper.getFolderName(uri),
      isFavorite: false,
      lastPlayedAt: Date.now(),
      playCount: 0,
      isCompleted: false
    };
  }

  static createWithOptions(uri: string, title: string, options?: Partial<MediaItem>): MediaItem {
    const base = MediaItemHelper.create(uri, title);
    if (!options) {
      return base;
    }
    return MediaItemHelper.merge(base, options, uri, title);
  }

  static isNetworkUri(uri: string): boolean {
    return uri.startsWith('http://') || uri.startsWith('https://');
  }

  static getFolderName(uri: string): string {
    if (MediaItemHelper.isNetworkUri(uri)) {
      return '网络流';
    }

    const normalized = uri.split('?')[0];
    const parts = normalized.split('/').filter((part: string) => part.length > 0);
    if (parts.length <= 1) {
      return '根目录';
    }
    return decodeURIComponent(parts[parts.length - 2]);
  }

  static getDisplayTitle(uri: string): string {
    const normalized = uri.split('?')[0];
    const parts = normalized.split('/').filter((part: string) => part.length > 0);
    if (parts.length === 0) {
      return '未知视频';
    }
    return decodeURIComponent(parts[parts.length - 1]);
  }

  private static generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
  }

  private static merge(base: MediaItem, options: Partial<MediaItem>, uri: string, title: string): MediaItem {
    return {
      id: options.id ?? base.id,
      uri,
      title,
      duration: options.duration ?? base.duration,
      lastPosition: options.lastPosition ?? base.lastPosition,
      addedTime: options.addedTime ?? base.addedTime,
      sourceType: options.sourceType ?? base.sourceType,
      folderName: options.folderName ?? base.folderName,
      isFavorite: options.isFavorite ?? base.isFavorite,
      lastPlayedAt: options.lastPlayedAt ?? base.lastPlayedAt,
      playCount: options.playCount ?? base.playCount,
      isCompleted: options.isCompleted ?? base.isCompleted,
      thumbnailUri: options.thumbnailUri ?? base.thumbnailUri,
      width: options.width ?? base.width,
      height: options.height ?? base.height,
      fileSizeBytes: options.fileSizeBytes ?? base.fileSizeBytes,
      importRootUri: options.importRootUri ?? base.importRootUri
    };
  }
}
