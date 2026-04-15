import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

export interface DlnaDevice {
  usn: string;
  location: string;
  friendlyName: string;
  deviceType: string;
  avTransportControlUrl: string;
}

interface SsdpResponse {
  usn: string;
  location: string;
  st: string;
}

export class DlnaService {
  static async discoverDevices(timeoutMs: number = 3000): Promise<DlnaDevice[]> {
    const udp = socket.constructUDPSocketInstance();
    const responses = new Map<string, SsdpResponse>();
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

    udp.on('message', (info: socket.SocketMessageInfo) => {
      const message = decoder.decodeToString(new Uint8Array(info.message), { stream: false });
      const parsed = DlnaService.parseSsdpResponse(message);
      if (!parsed || parsed.location.length === 0) {
        return;
      }
      const key = parsed.usn.length > 0 ? parsed.usn : parsed.location;
      if (!responses.has(key)) {
        responses.set(key, parsed);
      }
    });

    await udp.bind({ address: '0.0.0.0', port: 0, family: 1 });

    const searchTargets = [
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      'upnp:rootdevice'
    ];

    for (const st of searchTargets) {
      const payload =
        'M-SEARCH * HTTP/1.1\r\n' +
        'HOST: 239.255.255.250:1900\r\n' +
        'MAN: "ssdp:discover"\r\n' +
        'MX: 2\r\n' +
        `ST: ${st}\r\n` +
        '\r\n';
      await udp.send({
        data: payload,
        address: { address: '239.255.255.250', port: 1900, family: 1 }
      });
    }

    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), timeoutMs);
    });
    await udp.close().catch(() => {});

    const devices: DlnaDevice[] = [];
    for (const response of responses.values()) {
      const device = await DlnaService.fetchDeviceDescription(response).catch(() => null);
      if (!device) {
        continue;
      }
      devices.push(device);
    }

    // Deduplicate by control URL or location.
    const unique = new Map<string, DlnaDevice>();
    for (const device of devices) {
      const key = device.avTransportControlUrl || device.location;
      if (!unique.has(key)) {
        unique.set(key, device);
      }
    }
    return Array.from(unique.values()).sort((a: DlnaDevice, b: DlnaDevice) => a.friendlyName.localeCompare(b.friendlyName));
  }

  static async cast(device: DlnaDevice, mediaUrl: string): Promise<void> {
    await DlnaService.soap(device.avTransportControlUrl,
      'urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI',
      `<?xml version="1.0" encoding="utf-8"?>` +
      `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` +
      `<s:Body>` +
      `<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">` +
      `<InstanceID>0</InstanceID>` +
      `<CurrentURI>${DlnaService.escapeXml(mediaUrl)}</CurrentURI>` +
      `<CurrentURIMetaData></CurrentURIMetaData>` +
      `</u:SetAVTransportURI>` +
      `</s:Body>` +
      `</s:Envelope>`
    );
    await DlnaService.play(device);
  }

  static async play(device: DlnaDevice): Promise<void> {
    await DlnaService.soap(device.avTransportControlUrl,
      'urn:schemas-upnp-org:service:AVTransport:1#Play',
      `<?xml version="1.0" encoding="utf-8"?>` +
      `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` +
      `<s:Body>` +
      `<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">` +
      `<InstanceID>0</InstanceID>` +
      `<Speed>1</Speed>` +
      `</u:Play>` +
      `</s:Body>` +
      `</s:Envelope>`
    );
  }

  static async pause(device: DlnaDevice): Promise<void> {
    await DlnaService.soap(device.avTransportControlUrl,
      'urn:schemas-upnp-org:service:AVTransport:1#Pause',
      `<?xml version="1.0" encoding="utf-8"?>` +
      `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` +
      `<s:Body>` +
      `<u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">` +
      `<InstanceID>0</InstanceID>` +
      `</u:Pause>` +
      `</s:Body>` +
      `</s:Envelope>`
    );
  }

  static async stop(device: DlnaDevice): Promise<void> {
    await DlnaService.soap(device.avTransportControlUrl,
      'urn:schemas-upnp-org:service:AVTransport:1#Stop',
      `<?xml version="1.0" encoding="utf-8"?>` +
      `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` +
      `<s:Body>` +
      `<u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">` +
      `<InstanceID>0</InstanceID>` +
      `</u:Stop>` +
      `</s:Body>` +
      `</s:Envelope>`
    );
  }

  private static async soap(controlUrl: string, soapAction: string, body: string): Promise<void> {
    const res = await fetch(controlUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPACTION': `"${soapAction}"`
      },
      body
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`DLNA 控制失败：HTTP ${res.status}${text.length > 0 ? ` ${text}` : ''}`);
    }
  }

  private static parseSsdpResponse(message: string): SsdpResponse | null {
    const lines = message.split(/\r?\n/);
    if (lines.length === 0 || !/^HTTP\/1\.1 200/i.test(lines[0])) {
      return null;
    }
    const headers: Record<string, string> = {};
    lines.slice(1).forEach((line: string) => {
      const idx = line.indexOf(':');
      if (idx <= 0) {
        return;
      }
      const key = line.slice(0, idx).trim().toLowerCase();
      const value = line.slice(idx + 1).trim();
      headers[key] = value;
    });
    return {
      usn: headers['usn'] ?? '',
      location: headers['location'] ?? '',
      st: headers['st'] ?? ''
    };
  }

  private static async fetchDeviceDescription(response: SsdpResponse): Promise<DlnaDevice | null> {
    const res = await fetch(response.location);
    if (!res.ok) {
      return null;
    }
    const xml = await res.text();
    const deviceType = DlnaService.extractTag(xml, 'deviceType');
    if (!deviceType.includes('MediaRenderer')) {
      return null;
    }
    const friendlyName = DlnaService.extractTag(xml, 'friendlyName') || response.st || '未知设备';
    const serviceBlocks = xml.match(/<service>[\s\S]*?<\/service>/g) ?? [];
    let avTransportControlUrl = '';
    for (const block of serviceBlocks) {
      const serviceType = DlnaService.extractTag(block, 'serviceType');
      if (serviceType.includes('AVTransport')) {
        const controlUrl = DlnaService.extractTag(block, 'controlURL');
        avTransportControlUrl = DlnaService.resolveUrl(response.location, controlUrl);
        break;
      }
    }
    if (avTransportControlUrl.length === 0) {
      return null;
    }
    return {
      usn: response.usn,
      location: response.location,
      friendlyName,
      deviceType,
      avTransportControlUrl
    };
  }

  private static extractTag(xml: string, tag: string): string {
    const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const match = xml.match(re);
    return match ? match[1].trim() : '';
  }

  private static resolveUrl(baseUrl: string, maybeRelative: string): string {
    try {
      return new URL(maybeRelative, baseUrl).toString();
    } catch {
      return maybeRelative;
    }
  }

  private static escapeXml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}

