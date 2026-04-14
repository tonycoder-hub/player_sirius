import type { MediaItem } from '../model/MediaItem';
import { Playlist } from '../model/Playlist';

export const PLAYBACK_SPEEDS = [0.75, 1.0, 1.25, 1.75, 2.0];

export class PlayerService {
  private playlist: Playlist = new Playlist();
  private currentVolume: number = 1.0;
  private currentSpeed: number = 1.0;
  addOrActivate(item: MediaItem): MediaItem {
    const existingIndex = this.playlist.findIndexByUri(item.uri);
    if (existingIndex >= 0) {
      this.playlist.setCurrentIndex(existingIndex);
      const currentItem = this.playlist.getCurrentItem() as MediaItem;
      Object.assign(currentItem, {
        ...item,
        id: currentItem.id || item.id,
        addedTime: currentItem.addedTime || item.addedTime
      });
      return currentItem;
    }

    this.playlist.addItem(item);
    this.playlist.setCurrentIndex(this.playlist.getSize() - 1);
    return item;
  }

  getPlaylist(): Playlist {
    return this.playlist;
  }

  getCurrentItem(): MediaItem | null {
    return this.playlist.getCurrentItem();
  }

  selectByIndex(index: number): MediaItem | null {
    if (!this.playlist.setCurrentIndex(index)) {
      return null;
    }
    return this.playlist.getCurrentItem();
  }

  playNext(): MediaItem | null {
    return this.playlist.next();
  }

  playPrevious(): MediaItem | null {
    return this.playlist.previous();
  }

  setSpeed(speed: number): void {
    this.currentSpeed = PLAYBACK_SPEEDS.includes(speed) ? speed : 1.0;
  }

  getSpeed(): number {
    return this.currentSpeed;
  }

  setVolume(volume: number): void {
    this.currentVolume = Math.max(0, Math.min(volume, 1));
  }

  getVolume(): number {
    return this.currentVolume;
  }
}
