SHELL=/bin/bash

SSL_CONF := v3.conf

PARENT := parent
PARENT_CRT := $(PARENT).crt
PARENT_KEY := $(PARENT).key

CLIENT := child
CLIENT_ARN_JSON := $(CLIENT).arn.json
CLIENT_CSR_JSON := $(CLIENT).csr.json
CLIENT_CSR := $(CLIENT).csr
CLIENT_CRT := $(CLIENT).crt 
CLIENT_CHAIN_CRT := $(CLIENT)-chain.crt 

$(PARENT_KEY):
	openssl genrsa -des3 -out $(PARENT_KEY) 4096

$(PARENT_CRT): $(PARENT_KEY) 
	openssl req -x509 -config $(SSL_CONF) -new -nodes -key $(PARENT_KEY) -sha256 -days 1024 -out $(PARENT_CRT) 

$(CLIENT_ARN_JSON): certificate-authority.json revocation.json
	aws acm-pca create-certificate-authority \
		--certificate-authority-configuration file://certificate-authority.json \
		--revocation-configuration file://revocation.json \
		--certificate-authority-type SUBORDINATE > $(CLIENT_ARN_JSON) 

$(CLIENT_CSR_JSON): $(CLIENT_ARN_JSON)
	aws acm-pca get-certificate-authority-csr \
		--certificate-authority-arn $(shell cat $(CLIENT_ARN_JSON) | jq '.CertificateAuthorityArn' | tr -d '"') > $(CLIENT_CSR_JSON)

$(CLIENT_CSR): $(CLIENT_CSR_JSON)
	echo -e '$(shell cat $(CLIENT_CSR_JSON) | jq '.Csr' | tr -d '"')' > $(CLIENT_CSR)

$(CLIENT_CRT): $(CLIENT_CSR) $(PARENT_CRT) $(PARENT_KEY)
	openssl x509 \
		-req \
		-extfile $(SSL_CONF) \
		-extensions hidden_alphabet_extensions \
		-in $(CLIENT_CSR) \
		-CA $(PARENT_CRT) \
		-CAkey $(PARENT_KEY) \
		-CAcreateserial \
		-out $(CLIENT_CRT) \
		-days 500 \
		-sha256

$(CLIENT_CHAIN_CRT): $(PARENT_CRT)
	cat $(PARENT_CRT) > $(CLIENT_CHAIN_CRT)

create: $(CLIENT_CSR_JSON) $(CLIENT_CRT) $(CLIENT_CHAIN_CRT)
	aws acm-pca import-certificate-authority-certificate \
		--certificate-authority-arn $(shell cat $(CLIENT_ARN_JSON) | jq '.CertificateAuthorityArn' | tr -d '"') \
		--certificate file://$(CLIENT_CRT) \
		--certificate-chain file://$(CLIENT_CHAIN_CRT)
	aws acm-pca create-permission \
		--certificate-authority-arn $(shell cat $(CLIENT_ARN_JSON) | jq '.CertificateAuthorityArn' | tr -d '"') \
		--actions "IssueCertificate" "GetCertificate" "ListPermissions" \
		--principal acm.amazonaws.com

list:
	aws acm-pca list-certificate-authorities

status:
	aws acm-pca certificate-authority \
		--certificate-authority-arn $(shell cat $(CLIENT_ARN_JSON) | jq '.CertificateAuthorityArn' | tr -d '"')

delete:
	aws acm-pca delete-certificate-authority \
		--delete-certificate-authority $(shell cat $(CLIENT_ARN_JSON) | jq '.CertificateAuthorityArn' | tr -d '"')

clean:
	rm $(PARENT_KEY)
	rm $(PARENT_CRT)
	rm $(CLIENT_ARN_JSON)
	rm $(CLIENT_CSR_JSON)
	rm $(CLIENT_CSR)
	rm $(CLIENT_CRT)
	rm $(CLIENT_CHAIN_CRT)
