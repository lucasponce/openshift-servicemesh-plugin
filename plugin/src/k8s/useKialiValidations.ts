import * as React from 'react';
import {K8sResourceCommon} from "@openshift-console/dynamic-plugin-sdk";
import {getKialiUrl} from "../utils";
import {getValidation} from "../types/IstioConfigList";
import * as API from "./api";

const useKialiValidations = (data:  K8sResourceCommon[], loaded: boolean): [K8sResourceCommon[], boolean] => {
    const [kialiData, setKialiData] = React.useState([]);
    const [loadedData, setLoadedData] = React.useState<boolean>(false);

    React.useEffect(() => {
        getKialiUrl()
            .then(kialiUrl => {
                console.log('KIALI QUERY + UPDATE IstioValidationsCache with: ' + kialiUrl.baseUrl);
                API.getAllIstioConfigs(kialiUrl.baseUrl, kialiUrl.token)
                    .then(response => response.data)
                    .then((kialiValidations) => {
                        console.log('KIALI FETCH ');
                        console.log(kialiValidations);

                        kialiData.forEach(d => d['validations'] = getValidation(kialiValidations, d.kind, d.metadata.name, d.metadata.namespace));

                        setKialiData(data);
                        setLoadedData(loaded);
                    });
            })
            .catch(e => console.error(e));
    }, [data, loaded]);
    return [kialiData, loadedData];
}

export default useKialiValidations;