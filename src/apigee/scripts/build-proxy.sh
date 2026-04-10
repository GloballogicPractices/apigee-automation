#!/bin/bash
TENANT_DIR=$1
CONFIG=$TENANT_DIR/config.json

# Extract values using jq
ID=$(jq -r '.tenant_id' $CONFIG)
TIER=$(jq -r '.billing_tier' $CONFIG)
BPATH=$(jq -r '.basepath' $CONFIG)

# Copy template to a build folder
cp -r proxies/templates/apiproxy ./build_apiproxy

# Inject values into XML
sed -i "s/REPLACE_TENANT_ID/$ID/g" ./build_apiproxy/policies/SetTenantContext.xml
sed -i "s/REPLACE_BILLING_TIER/$TIER/g" ./build_apiproxy/policies/SetTenantContext.xml
sed -i "s/REPLACE_BASEPATH/$BPATH/g" ./build_apiproxy/proxies/default.xml

# Update the main Proxy Bundle Name
sed -i "s/proxy-name/$ID-proxy/g" ./build_apiproxy/proxy-name.xml
mv ./build_apiproxy/proxy-name.xml ./build_apiproxy/$ID-proxy.xml

# Zip it
zip -r $ID-bundle.zip build_apiproxy