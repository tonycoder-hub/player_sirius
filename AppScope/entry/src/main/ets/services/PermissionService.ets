import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class PermissionService {
  private atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  async requestPermission(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    try {
      const result = await this.atManager.requestPermissionsFromUser(context, [permission]);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`requestPermission failed: ${error.code}, ${error.message}`);
      return false;
    }
  }

  async openPermissionSetting(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    try {
      const result = await this.atManager.requestPermissionOnSetting(context, [permission]);
      return result.length > 0 && result[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`openPermissionSetting failed: ${error.code}, ${error.message}`);
      return false;
    }
  }
}
