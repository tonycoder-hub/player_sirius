import { picker, fileShare, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';

export interface ScanResult {
  uris: string[];
  message: string;
  rootUri?: string;
  scannedCount?: number;
  skippedCount?: number;
  failedUris?: string[];
}

export class LocalScanService {
  static async pickFolderAndListVideos(context: common.UIAbilityContext, maxCount: number = 200): Promise<ScanResult> {
    // Folder selection is only available on some devices / syscaps.
    if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
      return { uris: [], message: '当前设备不支持文件夹选择扫描，请改用“批量选择视频导入”。' };
    }

    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(context);
      const result = await documentPicker.select(options);
      if (!result || result.length === 0) {
        return { uris: [], message: '未选择文件夹' };
      }
      const folderUri = result[0];

      // Try to persist permission to allow subsequent scans.
      const policy: fileShare.PolicyInfo = { uri: folderUri, operationMode: fileShare.OperationMode.READ_MODE };
      try {
        const checks = await fileShare.checkPersistentPermission([policy]);
        if (!checks?.[0]) {
          await fileShare.persistPermission([policy]);
        }
      } catch {
        // ignore: still can use temporary permission in this session
      }

      const uris = await LocalScanService.listFilesByExtensions(folderUri, ['.mp4', '.mkv', '.avi', '.mov', '.m3u8', '.flv'], maxCount);
      return {
        uris,
        message: `扫描播放列表已导入 ${uris.length} 个视频${uris.length >= maxCount ? `，已达到上限 ${maxCount}` : ''}`,
        rootUri: folderUri,
        scannedCount: uris.length,
        skippedCount: 0,
        failedUris: []
      };
    } catch (err) {
      const error = err as BusinessError;
      return { uris: [], message: `扫描失败：${error.message ?? `${err}`}` };
    }
  }

  static async rescanFolder(folderUri: string, maxCount: number = 200): Promise<ScanResult> {
    try {
      const uris = await LocalScanService.listFilesByExtensions(folderUri, ['.mp4', '.mkv', '.avi', '.mov', '.m3u8', '.flv'], maxCount);
      return {
        uris,
        message: uris.length > 0 ? `重新扫描到 ${uris.length} 个媒体文件` : '扫描源中未发现可导入视频',
        rootUri: folderUri
      };
    } catch (err) {
      const error = err as BusinessError;
      return { uris: [], message: `重新扫描失败：${error.message ?? `${err}`}`, rootUri: folderUri };
    }
  }

  private static async listFilesByExtensions(folderUri: string, exts: string[], maxCount: number): Promise<string[]> {
    // NOTE: FileKit folder enumeration APIs vary by API versions; we implement best-effort:
    // - Prefer listing the selected folder URI itself.
    // - Fall back to a FileUri directory form for path-like URIs.
    const normalizedExts = exts.map((e: string) => e.toLowerCase());
    const direct = await LocalScanService.tryListFilesByExtensions(folderUri, normalizedExts, maxCount);
    if (direct.length > 0) {
      return direct;
    }

    try {
      const fallbackDirectoryUri = new fileUri.FileUri(folderUri).getFullDirectoryUri();
      return await LocalScanService.tryListFilesByExtensions(fallbackDirectoryUri, normalizedExts, maxCount);
    } catch {
      return [];
    }
  }

  private static async tryListFilesByExtensions(baseUri: string, normalizedExts: string[], maxCount: number): Promise<string[]> {
    const candidates: string[] = [];
    try {
      const names = await fs.listFile(baseUri, { recursion: true });
      for (const rel of names) {
        if (candidates.length >= maxCount) {
          break;
        }
        const relativePath = `${rel}`;
        const lower = relativePath.toLowerCase();
        const hit = normalizedExts.some((ext: string) => lower.endsWith(ext));
        if (!hit) {
          continue;
        }
        candidates.push(LocalScanService.joinUri(baseUri, relativePath));
      }
    } catch {
      return [];
    }
    return candidates;
  }

  private static joinUri(baseUri: string, relativePath: string): string {
    const base = baseUri.replace(/\/+$/, '');
    const rel = relativePath.replace(/^\/+/, '');
    return `${base}/${rel}`;
  }
}
