.PHONY: ios-generate ios-test android-test oauth-test verify

ios-generate:
	cd apps/ios && xcodegen generate

ios-test: ios-generate
	cd apps/ios && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Presently.xcodeproj -scheme Presently -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

android-test:
	cd apps/android && ./gradlew testDebugUnitTest assembleDebug lintDebug

oauth-test:
	cd services/oauth-worker && go test ./... && go build ./...

verify: ios-test android-test oauth-test
