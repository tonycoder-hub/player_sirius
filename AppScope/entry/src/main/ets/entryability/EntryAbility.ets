import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import type AbilityConstant from '@ohos.app.ability.AbilityConstant';
import type Want from '@ohos.app.ability.Want';
import type { common } from '@kit.AbilityKit';
import { GlobalContext } from '../common/GlobalContext';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        return;
      }
    });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    GlobalContext.getStorageService().setContext(this.context);
    GlobalContext.getBackgroundPlaybackService().setContext(this.context as unknown as common.UIAbilityContext);
  }

  onDestroy(): void {
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
    const currentItem = GlobalContext.getPlayerService().getCurrentItem();
    if (currentItem) {
      GlobalContext.getStorageService().savePlayHistory(currentItem);
    }
  }
}
