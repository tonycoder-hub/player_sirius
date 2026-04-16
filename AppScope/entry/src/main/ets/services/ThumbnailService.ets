import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';
import type { MediaItem } from '../model/MediaItem';

export class ThumbnailService {
  static async ensureThumbnail(context: common.UIAbilityContext, item: MediaItem): Promise<string> {
    if (item.sourceType !== 'local' || item.uri.length === 0) {
      return '';
    }
    if (item.thumbnailUri && item.thumbnailUri.length > 0) {
      return item.thumbnailUri;
    }

    const cacheDir = context.cacheDir ?? context.filesDir ?? '';
    if (cacheDir.length === 0) {
      return '';
    }
    const thumbDir = `${cacheDir}/thumb_cache`;
    try {
      fs.mkdirSync(thumbDir);
    } catch {
      // ignore
    }
    const outputPath = `${thumbDir}/${item.id}.jpg`;

    let file: fs.File | null = null;
    let generator: media.AVImageGenerator | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      file = fs.openSync(item.uri, fs.OpenMode.READ_ONLY);
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd };
      const pixelMap = await generator.fetchFrameByTime(
        0,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
        { width: 240, height: 135 }
      );

      const outFile = fs.openSync(outputPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        packer = image.createImagePacker();
        await packer.packToFile(pixelMap, outFile.fd, {
          format: 'image/jpeg',
          quality: 85
        });
      } finally {
        fs.closeSync(outFile);
      }

      try {
        const info = pixelMap.getImageInfoSync();
        item.width = Number(info.size.width ?? 0);
        item.height = Number(info.size.height ?? 0);
      } catch {
        // ignore
      }

      return `file://${outputPath}`;
    } catch {
      return '';
    } finally {
      try {
        if (packer) {
          packer.release();
        }
      } catch {
        // ignore
      }
      try {
        if (generator) {
          await generator.release();
        }
      } catch {
        // ignore
      }
      try {
        if (file) {
          fs.closeSync(file);
        }
      } catch {
        // ignore
      }
    }
  }
}

