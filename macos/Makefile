ARCH := arm64
CXX := clang++
CC := clang
SDK := $(shell xcrun --show-sdk-path)
MIN := 12.0
UP := ../upstream
# Fetch the pinned third-party source tree on first build (see NOTICE).
ifeq ($(wildcard $(UP)/scintilla/src/Editor.cxx),)
$(info upstream/ missing, running ../scripts/fetch-upstream.sh)
FETCH_STATUS := $(shell ../scripts/fetch-upstream.sh >&2; echo $$?)
ifneq ($(FETCH_STATUS),0)
$(error scripts/fetch-upstream.sh failed)
endif
endif
# Flavours: FLAVOR=developer (default, Developer ID / direct download, full features)
# and FLAVOR=appstore (App Sandbox, bundled plugins only, single process).
FLAVOR ?= developer
ifeq ($(FLAVOR),appstore)
B := build/appstore
FLAVOR_FLAGS := -DSIMEIO_APP_STORE=1
ENTITLEMENTS := Simeiomatarion.entitlements
else ifeq ($(FLAVOR),developer)
B := build
FLAVOR_FLAGS :=
ENTITLEMENTS := Simeiomatarion.developer.entitlements
else
$(error FLAVOR must be developer or appstore)
endif

# Signing: ad-hoc by default. For a real identity, e.g.
#   make FLAVOR=appstore SIGN_IDENTITY="Apple Distribution: …" TEAM_ID=XXXXXXXXXX
# TEAM_ID adds the application-identifier and team-identifier entitlements (App Store).
SIGN_IDENTITY ?= -
TEAM_ID ?=
BUNDLE_ID := gr.streamcode.simeiomatarion
ifeq ($(SIGN_IDENTITY),-)
SIGN_TIMESTAMP := --timestamp=none
else
SIGN_TIMESTAMP := --timestamp
endif
ifneq ($(and $(filter appstore,$(FLAVOR)),$(TEAM_ID)),)
SIGN_ENTITLEMENTS := $(B)/Simeiomatarion.entitlements
else
SIGN_ENTITLEMENTS := $(ENTITLEMENTS)
endif
SIGN := codesign --force --options runtime $(SIGN_TIMESTAMP) --sign "$(SIGN_IDENTITY)"

SYS := -arch $(ARCH) -isysroot "$(SDK)" -mmacosx-version-min=$(MIN)
CXXFLAGS := $(SYS) -std=c++17 -O2
THIRD_FLAGS := $(CXXFLAGS) -w -DNDEBUG
SCI_INCLUDES := -I$(UP)/scintilla/include -I$(UP)/scintilla/src -I$(UP)/boostregex
LEX_INCLUDES := -Icompat -I$(UP)/lexilla/include -I$(UP)/lexilla/lexlib -I$(UP)/scintilla/include
APP_INCLUDES := -Isrc $(SCI_INCLUDES) -I$(UP)/lexilla/include -I$(UP)/scintilla/cocoa
OBJCXX := $(CXXFLAGS) $(FLAVOR_FLAGS) -fobjc-arc -Wall -Wextra -Wno-unused-parameter
PREFIX := -include src/sdk_prefix.h
APP := $(B)/Simeiomatarion.app

# Version: ../VERSION (semver) and ../BUILD_NUMBER are the single source of truth.
# Override on the command line for CI, e.g. `make BUILD_NUMBER=42`.
VERSION := $(strip $(shell cat ../VERSION))
BUILD_NUMBER := $(strip $(shell cat ../BUILD_NUMBER))

SCI_SRC := $(wildcard $(UP)/scintilla/src/*.cxx)
COCOA_SRC := $(UP)/scintilla/cocoa/PlatCocoa.mm $(UP)/scintilla/cocoa/ScintillaCocoa.mm $(UP)/scintilla/cocoa/ScintillaView.mm $(UP)/scintilla/cocoa/InfoBar.mm
BOOST_SRC := $(UP)/boostregex/BoostRegExSearch.cxx $(UP)/boostregex/UTF8DocumentIterator.cxx
LEX_SRC := $(wildcard $(UP)/lexilla/src/*.cxx) $(wildcard $(UP)/lexilla/lexlib/*.cxx) $(wildcard $(UP)/lexilla/lexers/*.cxx)
APP_MM := src/main.mm src/AppDelegate.mm src/DocumentTab.mm src/Search.mm src/LangCatalog.mm src/EditorSettings.mm src/MacroStore.mm src/EditorActions.mm src/StyleTheme.mm src/OutlineIndex.mm src/SnippetStore.mm src/PreviewHTML.mm src/UserLanguages.mm src/ClipboardHistory.mm src/MinimapView.mm src/Localization.mm src/TextTools.mm src/OfficeOpen.mm src/SandboxAccess.mm
APP_CC := src/Encoding.cc

SCI_OBJ := $(patsubst $(UP)/scintilla/src/%.cxx,$(B)/obj/sci/%.o,$(SCI_SRC))
COCOA_OBJ := $(patsubst $(UP)/scintilla/cocoa/%.mm,$(B)/obj/cocoa/%.o,$(COCOA_SRC))
BOOST_OBJ := $(patsubst $(UP)/boostregex/%.cxx,$(B)/obj/boost/%.o,$(BOOST_SRC))
LEX_OBJ := $(patsubst $(UP)/lexilla/src/%.cxx,$(B)/obj/lex/src/%.o,$(filter $(UP)/lexilla/src/%,$(LEX_SRC))) \
	$(patsubst $(UP)/lexilla/lexlib/%.cxx,$(B)/obj/lex/lib/%.o,$(filter $(UP)/lexilla/lexlib/%,$(LEX_SRC))) \
	$(patsubst $(UP)/lexilla/lexers/%.cxx,$(B)/obj/lex/lexers/%.o,$(filter $(UP)/lexilla/lexers/%,$(LEX_SRC)))
APP_OBJ := $(patsubst src/%.mm,$(B)/obj/app/%.o,$(APP_MM)) $(patsubst src/%.cc,$(B)/obj/app/%.o,$(APP_CC))
ENGINE_OBJ := $(SCI_OBJ) $(COCOA_OBJ) $(BOOST_OBJ) $(LEX_OBJ)
TEST_OBJ := $(B)/obj/app/port_tests.o $(B)/obj/app/Encoding.o $(B)/obj/app/LangCatalog.o $(B)/obj/app/Search.o $(B)/obj/app/EditorActions.o $(B)/obj/app/EditorSettings.o $(B)/obj/app/StyleTheme.o $(B)/obj/app/DocumentTab.o $(B)/obj/app/OutlineIndex.o $(B)/obj/app/SnippetStore.o $(B)/obj/app/PreviewHTML.o $(B)/obj/app/UserLanguages.o $(B)/obj/app/ClipboardHistory.o $(B)/obj/app/Localization.o $(B)/obj/app/TextTools.o $(B)/obj/app/OfficeOpen.o

.PHONY: all clean test resources plugin version sign appstore developer $(APP)/Contents/Info.plist

version:
	@echo "$(VERSION) ($(BUILD_NUMBER))"

all: $(APP)/Contents/MacOS/Simeiomatarion $(APP)/Contents/Info.plist $(APP)/Contents/PkgInfo resources plugin $(B)/port_tests sign

# Plugins first, then the app with the flavour's entitlements, all with the hardened runtime.
sign: $(APP)/Contents/MacOS/Simeiomatarion $(APP)/Contents/Info.plist $(APP)/Contents/PkgInfo resources plugin $(SIGN_ENTITLEMENTS)
	for dylib in $(APP)/Contents/PlugIns/*.dylib; do $(SIGN) "$$dylib" || exit 1; done
	$(SIGN) --entitlements $(SIGN_ENTITLEMENTS) $(APP)
	codesign --verify --strict --deep $(APP)

$(B)/Simeiomatarion.entitlements: Simeiomatarion.appstore-team.entitlements.in
	@mkdir -p $(B)
	sed -e 's/@TEAM_ID@/$(TEAM_ID)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' $< > $@
	plutil -lint $@

appstore:
	$(MAKE) FLAVOR=appstore test

developer:
	$(MAKE) FLAVOR=developer test

$(B)/obj/sci/%.o: $(UP)/scintilla/src/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(SCI_INCLUDES) -c $< -o $@

$(B)/obj/cocoa/%.o: $(UP)/scintilla/cocoa/%.mm
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fobjc-arc -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(PREFIX) $(SCI_INCLUDES) -I$(UP)/scintilla/cocoa -c $< -o $@

$(B)/obj/boost/%.o: $(UP)/boostregex/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(SCI_INCLUDES) -c $< -o $@

$(B)/obj/lex/src/%.o: $(UP)/lexilla/src/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

$(B)/obj/lex/lib/%.o: $(UP)/lexilla/lexlib/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

$(B)/obj/lex/lexers/%.o: $(UP)/lexilla/lexers/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

$(B)/obj/app/%.o: src/%.mm
	@mkdir -p $(dir $@)
	$(CXX) $(OBJCXX) $(APP_INCLUDES) -c $< -o $@

$(B)/obj/app/%.o: src/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -Wall -Wextra -Wno-unused-parameter -Isrc -c $< -o $@

$(B)/obj/app/port_tests.o: tests/port_tests.mm
	@mkdir -p $(dir $@)
	$(CXX) $(OBJCXX) $(APP_INCLUDES) -c $< -o $@

$(APP)/Contents/MacOS/Simeiomatarion: $(APP_OBJ) $(ENGINE_OBJ)
	@mkdir -p $(dir $@)
	$(CXX) $(SYS) -fobjc-arc $^ -framework Cocoa -framework QuartzCore -framework CoreFoundation -framework WebKit -framework PDFKit -liconv -lz -o $@

$(B)/port_tests: $(TEST_OBJ) $(ENGINE_OBJ)
	$(CXX) $(SYS) -fobjc-arc $^ -framework Cocoa -framework QuartzCore -framework CoreFoundation -framework PDFKit -liconv -lz -o $@

$(APP)/Contents/Info.plist: Info.plist ../VERSION ../BUILD_NUMBER
	@mkdir -p $(APP)/Contents
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION must be MAJOR.MINOR.PATCH, got '$(VERSION)'"; exit 1; }
	@echo "$(BUILD_NUMBER)" | grep -Eq '^[0-9]+$$' || { echo "BUILD_NUMBER must be a positive integer, got '$(BUILD_NUMBER)'"; exit 1; }
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUILD_NUMBER@/$(BUILD_NUMBER)/g' $< > $@
	plutil -lint $@

$(APP)/Contents/PkgInfo:
	@mkdir -p $(APP)/Contents
	printf 'APPL????' > $@

ICON_SRC := resources/AppIcon.png
ICONSET := $(B)/AppIcon.iconset

$(APP)/Contents/Resources/AppIcon.icns: $(ICON_SRC)
	@mkdir -p $(ICONSET) $(APP)/Contents/Resources
	sips -s format png -z 16 16 $< --out $(ICONSET)/icon_16x16.png >/dev/null
	sips -s format png -z 32 32 $< --out $(ICONSET)/icon_16x16@2x.png >/dev/null
	sips -s format png -z 32 32 $< --out $(ICONSET)/icon_32x32.png >/dev/null
	sips -s format png -z 64 64 $< --out $(ICONSET)/icon_32x32@2x.png >/dev/null
	sips -s format png -z 128 128 $< --out $(ICONSET)/icon_128x128.png >/dev/null
	sips -s format png -z 256 256 $< --out $(ICONSET)/icon_128x128@2x.png >/dev/null
	sips -s format png -z 256 256 $< --out $(ICONSET)/icon_256x256.png >/dev/null
	sips -s format png -z 512 512 $< --out $(ICONSET)/icon_256x256@2x.png >/dev/null
	sips -s format png -z 512 512 $< --out $(ICONSET)/icon_512x512.png >/dev/null
	sips -s format png -z 1024 1024 $< --out $(ICONSET)/icon_512x512@2x.png >/dev/null
	for icon in $(ICONSET)/*.png; do sips --deleteColorManagementProperties "$$icon" >/dev/null; done
	iconutil -c icns $(ICONSET) -o $@

resources: $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns
	@mkdir -p $(APP)/Contents/Resources
	cp resources/PrivacyInfo.xcprivacy $(APP)/Contents/Resources/PrivacyInfo.xcprivacy
	cp ../LICENSE $(APP)/Contents/Resources/LICENSE
	cp ../NOTICE $(APP)/Contents/Resources/NOTICE
	# Same files as upstream, with the XML root element renamed. Lookups use //Language and //LexerType.
	sed -E 's#<(/?)NotepadPlus([ >])#<\1Simeiomatarion\2#' $(UP)/PowerEditor/src/langs.model.xml > $(APP)/Contents/Resources/langs.model.xml
	sed -E 's#<(/?)NotepadPlus([ >])#<\1Simeiomatarion\2#' $(UP)/PowerEditor/src/stylers.model.xml > $(APP)/Contents/Resources/stylers.model.xml
	xmllint --noout $(APP)/Contents/Resources/langs.model.xml $(APP)/Contents/Resources/stylers.model.xml
	sips -s format tiff $(UP)/scintilla/cocoa/res/mac_cursor_busy.png --out $(APP)/Contents/Resources/mac_cursor_busy.tiff >/dev/null
	sips -s format tiff $(UP)/scintilla/cocoa/res/mac_cursor_flipped.png --out $(APP)/Contents/Resources/mac_cursor_flipped.tiff >/dev/null

plugin: $(APP)/Contents/Info.plist
	@mkdir -p $(APP)/Contents/PlugIns
	$(CC) $(SYS) -dynamiclib -Isrc plugins/sample/SamplePlugin.c -o $(APP)/Contents/PlugIns/SamplePlugin.dylib
	$(CC) $(SYS) -dynamiclib -Isrc plugins/mimetools/MimeTools.c -o $(APP)/Contents/PlugIns/MimeTools.dylib
	$(CC) $(SYS) -dynamiclib -Isrc plugins/converter/Converter.c -o $(APP)/Contents/PlugIns/Converter.dylib
	$(CC) $(SYS) -fobjc-arc -dynamiclib -Isrc plugins/json/JsonTools.m -framework Foundation -o $(APP)/Contents/PlugIns/JsonTools.dylib

test: all
	./$(B)/port_tests $(UP)/PowerEditor/src/langs.model.xml

clean:
	rm -rf build
