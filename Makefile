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

# Ad-hoc codesigning with macOS built-in codesign wrapper
TARGET_CODESIGN = codesign
GeminiRetro_CODESIGN_FLAGS = -s - --force

include $(THEOS_MAKE_PATH)/application.mk

ipa:: all
	@echo "==> Packaging .ipa for iPad Mini 1..."
	@rm -rf build/Payload GeminiRetro.ipa
	@mkdir -p build/Payload
	@cp -R $(THEOS_OBJ_DIR)/GeminiRetro.app build/Payload/
	@cd build && zip -r -9 ../GeminiRetro.ipa Payload > /dev/null
	@rm -rf build
	@echo "==> Successfully created GeminiRetro.ipa!"
