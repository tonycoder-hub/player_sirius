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
      externalSubtitle: false,
      subtitleOffset: false,
      multiAudioTrack: false,
      backgroundPlayback: false,
      audioFocus: false,
      smb: false,
      webdav: false,
      ftp: false,
      casting: false,
      equalizer: false
    }
  };

  private readonly nextKernel: PlaybackKernelDescriptor = {
    mode: 'avplayer-native',
    displayName: 'AVPlayer + Native',
    status: 'planned',
    featureFlags: {
      networkPlayback: true,
      hlsPlayback: true,
      externalSubtitle: true,
      subtitleOffset: true,
      multiAudioTrack: true,
      backgroundPlayback: true,
      audioFocus: true,
      smb: true,
      webdav: true,
      ftp: true,
      casting: true,
      equalizer: true
    }
  };

  getCurrentKernel(): PlaybackKernelDescriptor {
    return this.currentKernel;
  }

  getPlannedKernel(): PlaybackKernelDescriptor {
    return this.nextKernel;
  }

  getKernelByMode(mode: string): PlaybackKernelDescriptor {
    return mode === this.nextKernel.mode ? this.nextKernel : this.currentKernel;
  }

  supportsFeature(feature: keyof PlaybackFeatureFlags): boolean {
    return this.currentKernel.featureFlags[feature];
  }

  supportsFeatureByMode(mode: string, feature: keyof PlaybackFeatureFlags): boolean {
    return this.getKernelByMode(mode).featureFlags[feature];
  }
}
