import { AVPlayerService } from '../services/AVPlayerService';
import { PlayerService } from '../services/PlayerService';
import { PlayerKernelService } from '../services/PlayerKernelService';
import { StorageService } from '../services/StorageService';
import { BackgroundPlaybackService } from '../services/BackgroundPlaybackService';
import { NativePlayerBridgeService } from '../services/NativePlayerBridgeService';
import { LocalMediaHttpServerService } from '../services/LocalMediaHttpServerService';
import { SmbService } from '../services/SmbService';

export class GlobalContext {
  private static _avPlayerService: AVPlayerService | null = null;
  private static _playerService: PlayerService | null = null;
  private static _playerKernelService: PlayerKernelService | null = null;
  private static _storageService: StorageService | null = null;
  private static _backgroundPlaybackService: BackgroundPlaybackService | null = null;
  private static _nativePlayerBridgeService: NativePlayerBridgeService | null = null;
  private static _localMediaHttpServerService: LocalMediaHttpServerService | null = null;
  private static _smbService: SmbService | null = null;

  static getAVPlayerService(): AVPlayerService {
    if (!GlobalContext._avPlayerService) {
      GlobalContext._avPlayerService = new AVPlayerService();
    }
    return GlobalContext._avPlayerService;
  }

  static getPlayerService(): PlayerService {
    if (!GlobalContext._playerService) {
      GlobalContext._playerService = new PlayerService();
    }
    return GlobalContext._playerService;
  }

  static getStorageService(): StorageService {
    if (!GlobalContext._storageService) {
      GlobalContext._storageService = new StorageService();
    }
    return GlobalContext._storageService;
  }

  static getPlayerKernelService(): PlayerKernelService {
    if (!GlobalContext._playerKernelService) {
      GlobalContext._playerKernelService = new PlayerKernelService();
    }
    return GlobalContext._playerKernelService;
  }

  static getBackgroundPlaybackService(): BackgroundPlaybackService {
    if (!GlobalContext._backgroundPlaybackService) {
      GlobalContext._backgroundPlaybackService = new BackgroundPlaybackService();
    }
    return GlobalContext._backgroundPlaybackService;
  }

  static getNativePlayerBridgeService(): NativePlayerBridgeService {
    if (!GlobalContext._nativePlayerBridgeService) {
      GlobalContext._nativePlayerBridgeService = new NativePlayerBridgeService();
    }
    return GlobalContext._nativePlayerBridgeService;
  }

  static getLocalMediaHttpServerService(): LocalMediaHttpServerService {
    if (!GlobalContext._localMediaHttpServerService) {
      GlobalContext._localMediaHttpServerService = new LocalMediaHttpServerService();
    }
    return GlobalContext._localMediaHttpServerService;
  }

  static getSmbService(): SmbService {
    if (!GlobalContext._smbService) {
      GlobalContext._smbService = new SmbService();
    }
    return GlobalContext._smbService;
  }
}
