#!/bin/bash

echo "*** Wallet identity creation ***"

wallet_path=$(builtin cd $(pwd)/..; pwd)/wallet-identity
vc_issuer="consumer"
user_credential=""
operator_credential=""

while getopts 'p:n:' opt; do
    echo "Option: $opt"
    echo "OPTARG: $OPTARG"
    case $opt in
        p)
            if [ ! -z $OPTARG ] && [ -d $OPTARG ]; then
                wallet_path=$(cd $OPTARG; pwd)
            else
                echo "No wallet path provided."
                return 1
            fi
            ;;
        n)
            if [ ! -z $OPTARG ]; then
                vc_issuer=$OPTARG
            else
                echo "No participant name provided. Defaulting to '$vc_issuer'."
            fi
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            return 1
            ;;
    esac
done

echo "Preparing wallet identity (identity of the user that acts on behalf of $vc_issuer)..."
mkdir -p "$wallet_path"
chmod o+rw "$wallet_path"

docker run -v $wallet_path:/cert quay.io/wi_stefan/did-helper:0.1.1

echo -e "\nIssuing verifiable credential for USER"

user_credential=$(./get_credential_for_consumer.sh http://keycloak-$vc_issuer.127.0.0.1.nip.io:8080 user-credential)


if $(return 0 2>/dev/null); then
    echo "Exporting USER_CREDENTIAL..."
    export USER_CREDENTIAL=$user_credential
    echo -e "User credential:\n$USER_CREDENTIAL\n"
else
    echo -e "User credential issued. You can export it by running\n\nexport USER_CREDENTIAL=$user_credential\n"
fi

echo "\nIssuing verifiable credential for OPERATOR"

operator_credential=$(./get_credential_for_consumer.sh http://keycloak-$vc_issuer.127.0.0.1.nip.io:8080 operator-credential)


if $(return 0 2>/dev/null); then
    echo "Exporting OPERATOR_CREDENTIAL..."
    export OPERATOR_CREDENTIAL=$operator_credential
    echo -e "Operator credential:\n$USER_CREDENTIAL\n"
else
    echo -e "Operator credential issued. You can export it by running\n\nexport OPERATOR_CREDENTIAL=$operator_credential\n"
fi

echo -e "\n*** Wallet identity created! ***"

cat <<EOF
Now it is possible to create and embed access token as bearer token in the Authorization header of the HTTP requests to the Data Provider.
Next steps:
1. Generate an access token for the USER running the following command
    ./get_access_token_oid4vp.sh http://mp-data-service.127.0.0.1.nip.io:8080 \$USER_CREDENTIAL user $wallet_path
2. Similarly, generate an access token for the OPERATOR as follows
    ./get_access_token_oid4vp.sh http://mp-data-service.127.0.0.1.nip.io:8080 \$OPERATOR_CREDENTIAL operator $wallet_path
EOF