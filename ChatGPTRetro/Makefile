THEOS = $(CURDIR)/../theos
export THEOS

TARGET = iphone:clang:9.3:8.4
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ChatGPTRetro

ChatGPTRetro_FILES = $(wildcard src/*.m)
ChatGPTRetro_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security
ChatGPTRetro_CFLAGS = -fobjc-arc -O2 -Wall -Wno-deprecated-declarations -Wno-deprecated-module-dot-map -I$(CURDIR)/include
ChatGPTRetro_LDFLAGS = -L$(CURDIR)/lib -lcurl -lssl -lcrypto -lz -Wl,-dead_strip -Wl,-undefined,dynamic_lookup
ChatGPTRetro_CODESIGN_FLAGS = -S$(CURDIR)/Resources/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

ipa:: all
	@echo "==> Packaging .ipa with live model support and iOS Settings.bundle..."
	@rm -rf build/Payload ChatGPTRetro.ipa
	@mkdir -p build/Payload/ChatGPTRetro.app
	@cp -R $(THEOS_OBJ_DIR)/ChatGPTRetro.app/* build/Payload/ChatGPTRetro.app/
	@cp Resources/Info.plist build/Payload/ChatGPTRetro.app/Info.plist
	@cp Resources/*.png build/Payload/ChatGPTRetro.app/ 2>/dev/null || true
	@cp -R Resources/Settings.bundle build/Payload/ChatGPTRetro.app/ 2>/dev/null || true
	@cp Resources/iTunesMetadata.plist build/iTunesMetadata.plist
	@plutil -convert binary1 build/Payload/ChatGPTRetro.app/Info.plist
	@chmod 755 build/Payload/ChatGPTRetro.app/ChatGPTRetro
	@chmod 755 build/Payload/ChatGPTRetro.app
	@codesign -s - --force --deep --preserve-metadata=identifier,flags build/Payload/ChatGPTRetro.app 2>/dev/null || true
	@cd build && zip -r -9 ../ChatGPTRetro.ipa Payload iTunesMetadata.plist > /dev/null
	@rm -rf build
	@echo "==> Successfully created ChatGPTRetro.ipa!"

run:: ipa
	@$(CURDIR)/../deploy_to_ipad.sh $(THEOS_OBJ_DIR)/ChatGPTRetro.app com.retro.chatgpt
