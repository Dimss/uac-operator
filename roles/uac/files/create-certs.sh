#!/usr/bin/env bash

ACTION=$1
WORK_DIR=$2
COMMON_NAME=$3
EXPIRATION_DAYS=36500

init () {
    if [ -d "$WORK_DIR" ]; then
        rm -fr ${WORK_DIR}
    fi
    mkdir ${WORK_DIR}
    cd ${WORK_DIR}
    cat << EOF > conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
EOF
}

create_ca () {
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -days ${EXPIRATION_DAYS} -out ca.crt -subj "/CN=admission_ca"
}

create_server_crts () {
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/CN=${COMMON_NAME}" -config conf
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days ${EXPIRATION_DAYS} -extensions v3_req -extfile conf
}

print_base64_certs (){
    echo -e "base64 encoded ca.crt\n"
    base64 -i ${WORK_DIR}/ca.crt
    echo -e "\n"
    echo -e "base64 encoded server.crt\n"
    base64 -i ${WORK_DIR}/server.crt
    echo -e "\n"
    echo -e "base64 encoded server.key\n"
    base64 -i ${WORK_DIR}/server.key
    echo -e "\n"
}

print_ca() {
    base64 -i ${WORK_DIR}/ca.crt
}

print_server_crt(){
    base64 -i ${WORK_DIR}/server.crt
}

print_server_key(){
    base64 -i ${WORK_DIR}/server.key
}

print_k8s_webhook_def(){
export SERVICE_NAME=${COMMON_NAME}
export BASE64_CA_BUNDLE=$(base64 -i ${WORK_DIR}/ca.crt)
cat <<EOF > ${WORK_DIR}/adwebhook.yaml
apiVersion: admissionregistration.k8s.io/v1beta1
kind: ValidatingWebhookConfiguration
metadata:
  name: uac
  labels:
    app: uac
webhooks:
  - name: ${SERVICE_NAME}
    clientConfig:
      url: https://${SERVICE_NAME}:8080/
      caBundle: ${BASE64_CA_BUNDLE}
    rules:
      - operations: [ "CREATE"]
        apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["oauthaccesstokens"]
    failurePolicy: Ignore
EOF
cat ${WORK_DIR}/adwebhook.yaml
echo "############### create webhook cmd ##################"
echo "# oc create -f ./webhook_deployment/adwebhook.yaml  #"
echo "#####################################################"
}



if [[ ${ACTION} == "create" ]]; then
    if [[ "$#" -ne 3 ]]; then
           echo "Missing action. Example usage:
              ./create-certs.sh create /tmp/certs uac.bnhp-system.svc.cluster.local
              ./create-certs.sh print_ca
              ./create-certs.sh print_server_ca
              ./create-certs.sh print_server_key"
            exit 1
    fi
    init
    create_ca
    create_server_crts
    exit 0
fi

if [[ ${ACTION} == "pca" ]]; then
    if [[ "$#" -ne 2 ]]; then
           echo "Missing workdir"
           exit 1
    fi
    base64 -i ${WORK_DIR}/ca.crt
    exit 0
fi

if [[ ${ACTION} == "pscert" ]]; then
    if [[ "$#" -ne 2 ]]; then
           echo "Missing workdir"
           exit 1
    fi
    base64 -i ${WORK_DIR}/server.crt
    exit 0
fi

if [[ ${ACTION} == "pskey" ]]; then
    if [[ "$#" -ne 2 ]]; then
           echo "Missing workdir"
           exit 1
    fi
    base64 -i ${WORK_DIR}/server.key
    exit 0
fi

# By default exit with error
exit 1
