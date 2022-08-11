import * as React from 'react';
import {K8sResourceCommon} from "@openshift-console/dynamic-plugin-sdk";
import {getKialiUrl} from "../utils";

const useKialiValidations = (data:  K8sResourceCommon[], loaded: boolean): [K8sResourceCommon[], boolean] => {
    const [kialiData, setKialiData] = React.useState([]);
    const [loadedData, setLoadedData] = React.useState<boolean>(false);

    React.useEffect(() => {
        getKialiUrl()
            .then(kialiUrl => {
                console.log('KIALI QUERY + UPDATE IstioValidationsCache with: ' + kialiUrl.baseUrl);
                fetch(kialiUrl.baseUrl + '/api/istio/config?validate=true&token=' + kialiUrl.token)
                    .then(response => response.json())
                    .then((kialiValidations) => {
                        console.log('KIALI FETCH ');
                        console.log(kialiValidations);

                        // TODO Here we need to mix the kialiValidations with the kialiData (K8sResourceCommon[])

                        setKialiData(data);
                        setLoadedData(loaded);
                    });
            })
            .catch(e => console.error(e));
    }, [data, loaded]);
    return [kialiData, loadedData];
}

export default useKialiValidations;