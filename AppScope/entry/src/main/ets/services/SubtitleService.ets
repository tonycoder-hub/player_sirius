import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export interface SubtitleCue {
  startMs: number;
  endMs: number;
  text: string;
}

export class SubtitleService {
  static async readTextFromUri(uri: string): Promise<string> {
    // FilePicker returns a URI with temporary permission. We read via fd to avoid assuming sandbox path.
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const totalSize = Math.max(0, Number(stat.size ?? 0));
      if (totalSize <= 0) {
        return '';
      }
      if (totalSize > 2 * 1024 * 1024) {
        // Basic guard to avoid accidental huge allocations from selecting a wrong file.
        throw new Error('字幕文件过大，建议选择 2MB 以内的 .srt 文件。');
      }

      const buffer = new ArrayBuffer(totalSize);
      const view = new Uint8Array(buffer);
      let offset = 0;
      const chunkSize = 64 * 1024;
      while (offset < totalSize) {
        const len = Math.min(chunkSize, totalSize - offset);
        const chunk = new ArrayBuffer(len);
        const readLen = fs.readSync(file.fd, chunk, { offset, length: len });
        if (readLen <= 0) {
          break;
        }
        view.set(new Uint8Array(chunk, 0, readLen), offset);
        offset += readLen;
      }

      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(new Uint8Array(buffer, 0, offset), { stream: false });
    } catch (err) {
      const error = err as BusinessError;
      const message = error?.message ?? `${err}`;
      throw new Error(message);
    } finally {
      try {
        fs.closeSync(file);
      } catch {
        // ignore
      }
    }
  }

  static parseSrt(content: string): SubtitleCue[] {
    const normalized = SubtitleService.normalizeLineEndings(content);
    const blocks = normalized.split(/\n{2,}/);
    const cues: SubtitleCue[] = [];

    for (const rawBlock of blocks) {
      const block = rawBlock.trim();
      if (block.length === 0) {
        continue;
      }

      const lines = block.split('\n');
      let cursor = 0;
      if (lines[cursor] && /^\d+$/.test(lines[cursor].trim())) {
        cursor++;
      }

      const timeLine = (lines[cursor] ?? '').trim();
      cursor++;
      const match = timeLine.match(
        /^(\d{2}:\d{2}:\d{2}[,\.]\d{1,3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{1,3}).*$/
      );
      if (!match) {
        continue;
      }

      const startMs = SubtitleService.parseTimestampMs(match[1]);
      const endMs = SubtitleService.parseTimestampMs(match[2]);
      if (startMs === null || endMs === null) {
        continue;
      }

      const text = SubtitleService.sanitizeText(lines.slice(cursor).join('\n'));
      if (text.length === 0) {
        continue;
      }

      cues.push({ startMs, endMs, text });
    }

    cues.sort((a: SubtitleCue, b: SubtitleCue) => a.startMs - b.startMs);
    return cues;
  }

  static findCueAt(cues: SubtitleCue[], timeMs: number): SubtitleCue | null {
    if (!Number.isFinite(timeMs) || cues.length === 0) {
      return null;
    }
    let left = 0;
    let right = cues.length - 1;
    while (left <= right) {
      const mid = (left + right) >> 1;
      const cue = cues[mid];
      if (timeMs < cue.startMs) {
        right = mid - 1;
      } else if (timeMs > cue.endMs) {
        left = mid + 1;
      } else {
        return cue;
      }
    }
    return null;
  }

  private static normalizeLineEndings(content: string): string {
    return content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  private static parseTimestampMs(timestamp: string): number | null {
    const parts = timestamp.trim().replace(',', '.').split(':');
    if (parts.length !== 3) {
      return null;
    }
    const hours = Number(parts[0]);
    const minutes = Number(parts[1]);
    const secondsParts = parts[2].split('.');
    const seconds = Number(secondsParts[0]);
    const millisStr = (secondsParts[1] ?? '0').padEnd(3, '0').slice(0, 3);
    const millis = Number(millisStr);
    if (![hours, minutes, seconds, millis].every((v: number) => Number.isFinite(v))) {
      return null;
    }
    return (((hours * 60 + minutes) * 60 + seconds) * 1000 + millis);
  }

  private static sanitizeText(text: string): string {
    // Remove basic HTML tags and trim.
    const cleaned = text.replace(/<[^>]+>/g, '').trim();
    return cleaned;
  }
}

