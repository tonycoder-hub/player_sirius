import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';

export class BrightnessService {
  static async getWindowBrightness(context: common.UIAbilityContext): Promise<number> {
    try {
      const currentWindow = await window.getLastWindow(context);
      const properties = currentWindow.getWindowProperties();
      return typeof properties.brightness === 'number' ? properties.brightness : -1;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Get window brightness failed: ${error.code}, ${error.message}`);
      return -1;
    }
  }

  static async setWindowBrightness(context: common.UIAbilityContext, brightness: number): Promise<void> {
    try {
      const currentWindow = await window.getLastWindow(context);
      await currentWindow.setWindowBrightness(Math.max(-1, Math.min(brightness, 1)));
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Set window brightness failed: ${error.code}, ${error.message}`);
    }
  }
}

