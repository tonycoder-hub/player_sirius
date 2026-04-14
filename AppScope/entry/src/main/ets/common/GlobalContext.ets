import { AVPlayerService } from '../services/AVPlayerService';
import { PlayerService } from '../services/PlayerService';
import { PlayerKernelService } from '../services/PlayerKernelService';
import { StorageService } from '../services/StorageService';

export class GlobalContext {
  private static _avPlayerService: AVPlayerService | null = null;
  private static _playerService: PlayerService | null = null;
  private static _playerKernelService: PlayerKernelService | null = null;
  private static _storageService: StorageService | null = null;

  static getAVPlayerService(): AVPlayerService {
    if (!this._avPlayerService) {
      this._avPlayerService = new AVPlayerService();
    }
    return this._avPlayerService;
  }

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

  static getPlayerKernelService(): PlayerKernelService {
    if (!this._playerKernelService) {
      this._playerKernelService = new PlayerKernelService();
    }
    return this._playerKernelService;
  }
}
