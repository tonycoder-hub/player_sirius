import type { MediaItem } from './MediaItem';

export class Playlist {
  private items: MediaItem[] = [];
  private currentIndex: number = -1;

  getItems(): MediaItem[] {
    return [...this.items];
  }

  getCurrentIndex(): number {
    return this.currentIndex;
  }

  getCurrentItem(): MediaItem | null {
    if (this.currentIndex >= 0 && this.currentIndex < this.items.length) {
      return this.items[this.currentIndex];
    }
    return null;
  }

  addItem(item: MediaItem): void {
    this.items.push(item);
  }

  setItems(items: MediaItem[], currentIndex: number = 0): void {
    this.items = [...items];
    if (this.items.length === 0) {
      this.currentIndex = -1;
      return;
    }
    this.currentIndex = Math.max(0, Math.min(currentIndex, this.items.length - 1));
  }

  findIndexByUri(uri: string): number {
    return this.items.findIndex((item: MediaItem) => item.uri === uri);
  }

  removeItem(index: number): void {
    if (index >= 0 && index < this.items.length) {
      this.items.splice(index, 1);
      if (this.items.length === 0) {
        this.currentIndex = -1;
      } else if (index < this.currentIndex) {
        this.currentIndex--;
      } else if (index === this.currentIndex) {
        this.currentIndex = Math.min(this.currentIndex, this.items.length - 1);
      }
    }
  }

  clear(): void {
    this.items = [];
    this.currentIndex = -1;
  }

  setCurrentIndex(index: number): boolean {
    if (index >= 0 && index < this.items.length) {
      this.currentIndex = index;
      return true;
    }
    return false;
  }

  next(): MediaItem | null {
    if (this.items.length === 0) {
      return null;
    }
    this.currentIndex = (this.currentIndex + 1) % this.items.length;
    return this.items[this.currentIndex];
  }

  previous(): MediaItem | null {
    if (this.items.length === 0) {
      return null;
    }
    if (this.currentIndex <= 0) {
      this.currentIndex = this.items.length - 1;
    } else {
      this.currentIndex--;
    }
    return this.items[this.currentIndex];
  }

  getSize(): number {
    return this.items.length;
  }
}
