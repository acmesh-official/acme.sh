export Arvan_Token="apikey 19680886-b6ce-5bb6-9cbe-7966ddb7062e"
./acme.sh --set-default-ca --server letsencrypt
./acme.sh --issue --force --dns dns_arvan -d mizekar.site -d '*.mizekar.site' --dnssleep 0
