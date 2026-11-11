THEOS = $(CURDIR)/theos
export THEOS

TARGET = iphone:clang:9.3:8.4
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GeminiRetro

GeminiRetro_FILES = $(wildcard src/*.m)
GeminiRetro_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
GeminiRetro_CFLAGS = -fobjc-arc -O2 -Wall -Wno-deprecated-declarations -Wno-deprecated-module-dot-map
GeminiRetro_LDFLAGS = -Wl,-dead_strip -Wl,-undefined,dynamic_lookup
GeminiRetro_CODESIGN_FLAGS = -S$(CURDIR)/Resources/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

ipa:: all
	@echo "==> Packaging .ipa with live model support and iOS Settings.bundle..."
	@rm -rf build/Payload GeminiRetro2.ipa
	@mkdir -p build/Payload/GeminiRetro.app
	@cp -R $(THEOS_OBJ_DIR)/GeminiRetro.app/* build/Payload/GeminiRetro.app/
	@cp Resources/Info.plist build/Payload/GeminiRetro.app/Info.plist
	@cp Resources/*.png build/Payload/GeminiRetro.app/ 2>/dev/null || true
	@cp -R Resources/Settings.bundle build/Payload/GeminiRetro.app/ 2>/dev/null || true
	@cp Resources/iTunesMetadata.plist build/iTunesMetadata.plist
	@plutil -convert binary1 build/Payload/GeminiRetro.app/Info.plist
	@chmod 755 build/Payload/GeminiRetro.app/GeminiRetro
	@chmod 755 build/Payload/GeminiRetro.app
	@codesign -s - --force --deep --preserve-metadata=identifier,flags build/Payload/GeminiRetro.app 2>/dev/null || true
	@cd build && zip -r -9 ../GeminiRetro2.ipa Payload iTunesMetadata.plist > /dev/null
	@rm -rf build
	@echo "==> Successfully created GeminiRetro2.ipa with iOS Settings.bundle!"
