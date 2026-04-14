import { PlayerService } from '../services/PlayerService';
import { StorageService } from '../services/StorageService';

export class GlobalContext {
  private static _playerService: PlayerService | null = null;
  private static _storageService: StorageService | null = null;

  static getPlayerService(): PlayerService {
    if (!this._playerService) {
      this._playerService = new PlayerService();
    }
    return this._playerService;
  }

  static getStorageService(): StorageService {
    if (!this._storageService) {
      this._storageService = new StorageService();
    }
    return this._storageService;
  }
}
