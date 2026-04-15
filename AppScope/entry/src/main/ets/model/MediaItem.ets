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
      id: this.generateId(),
      uri,
      title,
      duration: 0,
      lastPosition: 0,
      addedTime: Date.now(),
      sourceType: this.isNetworkUri(uri) ? 'network' : 'local',
      folderName: this.getFolderName(uri),
      isFavorite: false,
      lastPlayedAt: Date.now(),
      playCount: 0,
      isCompleted: false
    };
  }

  static createWithOptions(uri: string, title: string, options?: Partial<MediaItem>): MediaItem {
    return {
      ...this.create(uri, title),
      ...options,
      uri,
      title
    };
  }

  static isNetworkUri(uri: string): boolean {
    return uri.startsWith('http://') || uri.startsWith('https://');
  }

  static getFolderName(uri: string): string {
    if (this.isNetworkUri(uri)) {
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
}
