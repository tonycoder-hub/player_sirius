export interface PlaybackFeatureFlags {
  networkPlayback: boolean;
  hlsPlayback: boolean;
  externalSubtitle: boolean;
  subtitleOffset: boolean;
  multiAudioTrack: boolean;
  backgroundPlayback: boolean;
  audioFocus: boolean;
  smb: boolean;
  webdav: boolean;
  ftp: boolean;
  casting: boolean;
  equalizer: boolean;
}

export interface PlaybackKernelDescriptor {
  mode: string;
  displayName: string;
  status: string;
  featureFlags: PlaybackFeatureFlags;
}

export class PlayerKernelService {
  private readonly currentKernel: PlaybackKernelDescriptor = {
    mode: 'video-component',
    displayName: 'ArkUI Video',
    status: 'active',
    featureFlags: {
      networkPlayback: true,
      hlsPlayback: true,
      externalSubtitle: true,
      subtitleOffset: true,
      multiAudioTrack: false,
      backgroundPlayback: false,
      audioFocus: false,
      smb: false,
      webdav: false,
      ftp: false,
      casting: true,
      equalizer: false
    }
  };

  private readonly avPlayerKernel: PlaybackKernelDescriptor = {
    mode: 'avplayer-native',
    displayName: 'AVPlayer',
    status: 'active',
    featureFlags: {
      networkPlayback: true,
      hlsPlayback: true,
      externalSubtitle: true,
      subtitleOffset: true,
      multiAudioTrack: true,
      backgroundPlayback: false,
      audioFocus: true,
      smb: false,
      webdav: false,
      ftp: true,
      casting: true,
      equalizer: false
    }
  };

  private readonly nativeKernel: PlaybackKernelDescriptor = {
    mode: 'native-bridge',
    displayName: 'Native Bridge',
    status: 'experimental',
    featureFlags: {
      networkPlayback: true,
      hlsPlayback: true,
      externalSubtitle: true,
      subtitleOffset: true,
      multiAudioTrack: true,
      backgroundPlayback: true,
      audioFocus: true,
      smb: false,
      webdav: true,
      ftp: true,
      casting: true,
      equalizer: false
    }
  };

  private readonly kernels: PlaybackKernelDescriptor[] = [
    this.currentKernel,
    this.avPlayerKernel,
    this.nativeKernel
  ];

  getCurrentKernel(): PlaybackKernelDescriptor {
    return this.currentKernel;
  }

  getPlannedKernel(): PlaybackKernelDescriptor {
    return this.nativeKernel;
  }

  getAllKernels(): PlaybackKernelDescriptor[] {
    return this.kernels.slice();
  }

  getKernelByMode(mode: string): PlaybackKernelDescriptor {
    return this.kernels.find((kernel: PlaybackKernelDescriptor) => kernel.mode === mode) ?? this.currentKernel;
  }

  getFallbackMode(mode: string): string {
    if (mode === this.nativeKernel.mode) {
      return this.avPlayerKernel.mode;
    }
    if (mode === this.avPlayerKernel.mode) {
      return this.currentKernel.mode;
    }
    return this.avPlayerKernel.mode;
  }

  getRecommendedModeForMedia(uri: string, sourceType: string): string {
    const normalized = uri.trim().toLowerCase();
    if (sourceType === 'network') {
      // Prefer AVPlayer for network flows because it exposes buffering, bitrate and focus handling.
      return this.avPlayerKernel.mode;
    }
    if (normalized.endsWith('.m3u8') || normalized.endsWith('.mpd') || normalized.endsWith('.flv')) {
      return this.avPlayerKernel.mode;
    }
    // Keep ArkUI Video as default local path and fallback candidate for simpler local files.
    return this.currentKernel.mode;
  }

  supportsFeature(feature: keyof PlaybackFeatureFlags): boolean {
    return this.getFeatureValue(this.currentKernel.featureFlags, feature);
  }

  supportsFeatureByMode(mode: string, feature: keyof PlaybackFeatureFlags): boolean {
    return this.getFeatureValue(this.getKernelByMode(mode).featureFlags, feature);
  }

  private getFeatureValue(flags: PlaybackFeatureFlags, feature: keyof PlaybackFeatureFlags): boolean {
    switch (feature) {
      case 'networkPlayback':
        return flags.networkPlayback;
      case 'hlsPlayback':
        return flags.hlsPlayback;
      case 'externalSubtitle':
        return flags.externalSubtitle;
      case 'subtitleOffset':
        return flags.subtitleOffset;
      case 'multiAudioTrack':
        return flags.multiAudioTrack;
      case 'backgroundPlayback':
        return flags.backgroundPlayback;
      case 'audioFocus':
        return flags.audioFocus;
      case 'smb':
        return flags.smb;
      case 'webdav':
        return flags.webdav;
      case 'ftp':
        return flags.ftp;
      case 'casting':
        return flags.casting;
      case 'equalizer':
        return flags.equalizer;
      default:
        return false;
    }
  }
}
