# rvapp_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Test On A Physical iPhone

This project is configured to run on a connected iPhone in development mode.

### Prerequisites

1. Install the latest Xcode from the App Store.
2. Connect your iPhone by cable and tap Trust on the device.
3. Enable Developer Mode on iPhone: Settings > Privacy & Security > Developer Mode.
4. Sign in to Xcode with your Apple ID (free account is fine for local testing).

### First-Time Device Setup

1. Install Flutter dependencies:

	```bash
	flutter pub get
	```

2. Open the iOS workspace in Xcode:

	```bash
	open ios/Runner.xcworkspace
	```

3. In Xcode:
	- Select the Runner target.
	- Go to Signing & Capabilities.
	- Set Team to your personal Apple ID team.
	- Keep Automatically manage signing enabled.
	- If bundle ID conflicts, change it to a unique value like `com.yourname.nomadnetwork`.

4. Choose your connected iPhone as the run destination.
5. Press Run in Xcode once to let provisioning complete.

### Run From Terminal

After signing works in Xcode, you can run from terminal:

```bash
flutter devices
flutter run -d <your-device-id>
```

### IPA Notes

- The `create_ipa.sh` script packages an IPA from a built iOS app.
- With a free Apple ID, this is useful for local/manual testing only.
- TestFlight and broader distribution require a paid Apple Developer account.
