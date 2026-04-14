import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import type { MediaItem } from '../model/MediaItem';

const PREFERENCES_NAME = 'player_sirius_prefs';
const KEY_HISTORY = 'play_history';
const MAX_HISTORY_SIZE = 50;

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

  async savePlayHistory(item: MediaItem): Promise<void> {
    try {
      const prefs = await this.getPreferences();
      let history: MediaItem[] = [];

      try {
        const historyStr = await prefs.get(KEY_HISTORY, '[]');
        history = JSON.parse(historyStr as string) as MediaItem[];
      } catch {
        history = [];
      }

      const existingIndex = history.findIndex(h => h.uri === item.uri);
      if (existingIndex !== -1) {
        history.splice(existingIndex, 1);
      }

      history.unshift(item);

      if (history.length > MAX_HISTORY_SIZE) {
        history = history.slice(0, MAX_HISTORY_SIZE);
      }

      await prefs.put(KEY_HISTORY, JSON.stringify(history));
      await prefs.flush();
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      console.error(`Save play history failed: ${message}`);
    }
  }

  async getPlayHistory(): Promise<MediaItem[]> {
    try {
      const prefs = await this.getPreferences();
      const historyStr = await prefs.get(KEY_HISTORY, '[]');
      return JSON.parse(historyStr as string) as MediaItem[];
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
