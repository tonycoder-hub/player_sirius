export interface MediaItem {
  id: string;
  uri: string;
  title: string;
  duration: number;
  lastPosition: number;
  addedTime: number;
}

export class MediaItemHelper {
  static create(uri: string, title: string = '未知视频'): MediaItem {
    return {
      id: this.generateId(),
      uri,
      title,
      duration: 0,
      lastPosition: 0,
      addedTime: Date.now()
    };
  }

  private static generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
  }
}
