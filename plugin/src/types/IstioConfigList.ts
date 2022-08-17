import {
  Validations,
} from './IstioObjects';

export declare type IstioConfigsMap = Map<string, IstioConfigList>;

export interface IstioConfigList {
  validations: Validations;
}

export function validationKey(name: string, namespace?: string): string {
  if (namespace !== undefined) {
    return name + '.' + namespace;
  } else {
    return name;
  }
}

export function getValidation(istioConfigs: IstioConfigsMap, kind: string, name: string, namespace: string): string {
  if (istioConfigs[namespace] && istioConfigs[namespace].validations[kind.toLowerCase()] && istioConfigs[namespace].validations[kind.toLowerCase()][validationKey(name, namespace)]) {
    let validation = istioConfigs[namespace].validations[kind.toLowerCase()][validationKey(name, namespace)]
    if (validation.valid) {
      return "Valid"
    } else {
     if (validation.checks.filter(i => i.severity === 'error').length > 0) {
       return "Error"
     } else {
       return "Warning"
     }
    }
  } else {
    return "N/A"
  }
}
