#!/bin/bash
cd /Users/devinfuentes/RV\ App/rvapp_1
mkdir -p ipa_temp/Payload
cp -r build/ios/Release-iphoneos/Runner.app ipa_temp/Payload/
cd ipa_temp
zip -r ../Nomad-Network.ipa Payload/
cd ..
rm -rf ipa_temp
echo "IPA created at: /Users/devinfuentes/RV App/rvapp_1/Nomad-Network.ipa"
ls -lh Nomad-Network.ipa
