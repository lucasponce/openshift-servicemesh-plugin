import {getKialiUrl} from "../utils";
import {K8sResourceCommon} from "@openshift-console/dynamic-plugin-sdk";

/*
    Kiali API doesn't offer "watches" like the kubernetes API.
    Watches is the preferred mechanism of the OpenShift Console for detecting changes and update views.
    Also, Kiali validations come from a "cache" information populated in the Kiali backend.
    Then we need some mechanism to provide a "short-term" cache to complete the info about Istio Config resources
    in list and details.
 */
export class IstioValidationsCache {
    private static instance: IstioValidationsCache;
    // Timestamp for cache invalidation expressed in ms
    private lastFetch: number;
    // Cache duration expressed in seconds, this could be populated from the config in the future
    // (or perhaps not, and it's another layer of config, it may be over-arch)
    private cacheDuration: number;

    private constructor() {
        this.lastFetch = 0;         // ms as it's populated from a timestamp
        this.cacheDuration = 30;    // s as it's provided by config
    }

    public static getInstance(): IstioValidationsCache {
        if (!IstioValidationsCache.instance) {
            IstioValidationsCache.instance = new IstioValidationsCache();
        }
        return IstioValidationsCache.instance;
    }

    public static addValidations = (flatData:  K8sResourceCommon[]): K8sResourceCommon[] => {
        if (!IstioValidationsCache.getInstance().isValid()) {
            IstioValidationsCache.getInstance().fetchKialiValidations();
        }
        console.log('IstioValidationCache for ' + flatData.length);
        flatData.forEach(d => d['validations'] = 'N/A for ' + d.metadata.name);
        return flatData;
    }

    public static refresh() {
        IstioValidationsCache.getInstance().fetchKialiValidations();
    }

    private isValid() {
        const currentTime = new Date().getTime();
        if (currentTime > (this.lastFetch + this.cacheDuration * 1000)) {
            this.lastFetch = currentTime;
            return false;
        }
        return true;
    }

    private fetchKialiValidations() {
        getKialiUrl()
            .then(kialiUrl => {
                console.log('KIALI QUERY + UPDATE IstioValidationsCache with: ' + kialiUrl.baseUrl);
            })
            .catch(e => console.error(e));
    }
}