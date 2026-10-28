ARCH := arm64
CXX := clang++
CC := clang
SDK := $(shell xcrun --show-sdk-path)
MIN := 12.0
UP := ../upstream
SYS := -arch $(ARCH) -isysroot "$(SDK)" -mmacosx-version-min=$(MIN)
CXXFLAGS := $(SYS) -std=c++17 -O2
THIRD_FLAGS := $(CXXFLAGS) -w -DNDEBUG
SCI_INCLUDES := -I$(UP)/scintilla/include -I$(UP)/scintilla/src -I$(UP)/boostregex
LEX_INCLUDES := -Icompat -I$(UP)/lexilla/include -I$(UP)/lexilla/lexlib -I$(UP)/scintilla/include
APP_INCLUDES := -Isrc $(SCI_INCLUDES) -I$(UP)/lexilla/include -I$(UP)/scintilla/cocoa
OBJCXX := $(CXXFLAGS) -fobjc-arc -Wall -Wextra -Wno-unused-parameter
PREFIX := -include src/sdk_prefix.h
APP := build/Simeiomatarion.app

# Version: ../VERSION (semver) and ../BUILD_NUMBER are the single source of truth.
# Override on the command line for CI, e.g. `make BUILD_NUMBER=42`.
VERSION := $(strip $(shell cat ../VERSION))
BUILD_NUMBER := $(strip $(shell cat ../BUILD_NUMBER))

SCI_SRC := $(wildcard $(UP)/scintilla/src/*.cxx)
COCOA_SRC := $(UP)/scintilla/cocoa/PlatCocoa.mm $(UP)/scintilla/cocoa/ScintillaCocoa.mm $(UP)/scintilla/cocoa/ScintillaView.mm $(UP)/scintilla/cocoa/InfoBar.mm
BOOST_SRC := $(UP)/boostregex/BoostRegExSearch.cxx $(UP)/boostregex/UTF8DocumentIterator.cxx
LEX_SRC := $(wildcard $(UP)/lexilla/src/*.cxx) $(wildcard $(UP)/lexilla/lexlib/*.cxx) $(wildcard $(UP)/lexilla/lexers/*.cxx)
APP_MM := src/main.mm src/AppDelegate.mm src/DocumentTab.mm src/Search.mm src/LangCatalog.mm src/EditorSettings.mm src/MacroStore.mm src/EditorActions.mm src/StyleTheme.mm src/OutlineIndex.mm src/SnippetStore.mm src/PreviewHTML.mm src/UserLanguages.mm src/ClipboardHistory.mm src/MinimapView.mm src/Localization.mm src/TextTools.mm src/OfficeOpen.mm
APP_CC := src/Encoding.cc

SCI_OBJ := $(patsubst $(UP)/scintilla/src/%.cxx,build/obj/sci/%.o,$(SCI_SRC))
COCOA_OBJ := $(patsubst $(UP)/scintilla/cocoa/%.mm,build/obj/cocoa/%.o,$(COCOA_SRC))
BOOST_OBJ := $(patsubst $(UP)/boostregex/%.cxx,build/obj/boost/%.o,$(BOOST_SRC))
LEX_OBJ := $(patsubst $(UP)/lexilla/src/%.cxx,build/obj/lex/src/%.o,$(filter $(UP)/lexilla/src/%,$(LEX_SRC))) \
	$(patsubst $(UP)/lexilla/lexlib/%.cxx,build/obj/lex/lib/%.o,$(filter $(UP)/lexilla/lexlib/%,$(LEX_SRC))) \
	$(patsubst $(UP)/lexilla/lexers/%.cxx,build/obj/lex/lexers/%.o,$(filter $(UP)/lexilla/lexers/%,$(LEX_SRC)))
APP_OBJ := $(patsubst src/%.mm,build/obj/app/%.o,$(APP_MM)) $(patsubst src/%.cc,build/obj/app/%.o,$(APP_CC))
ENGINE_OBJ := $(SCI_OBJ) $(COCOA_OBJ) $(BOOST_OBJ) $(LEX_OBJ)
TEST_OBJ := build/obj/app/port_tests.o build/obj/app/Encoding.o build/obj/app/LangCatalog.o build/obj/app/Search.o build/obj/app/EditorActions.o build/obj/app/EditorSettings.o build/obj/app/StyleTheme.o build/obj/app/DocumentTab.o build/obj/app/OutlineIndex.o build/obj/app/SnippetStore.o build/obj/app/PreviewHTML.o build/obj/app/UserLanguages.o build/obj/app/ClipboardHistory.o build/obj/app/Localization.o build/obj/app/TextTools.o build/obj/app/OfficeOpen.o

.PHONY: all clean test resources plugin version $(APP)/Contents/Info.plist

version:
	@echo "$(VERSION) ($(BUILD_NUMBER))"

all: $(APP)/Contents/MacOS/NotepadPlusPlus $(APP)/Contents/Info.plist $(APP)/Contents/PkgInfo resources plugin build/port_tests
	codesign --force --sign - $(APP)

build/obj/sci/%.o: $(UP)/scintilla/src/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(SCI_INCLUDES) -c $< -o $@

build/obj/cocoa/%.o: $(UP)/scintilla/cocoa/%.mm
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fobjc-arc -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(PREFIX) $(SCI_INCLUDES) -I$(UP)/scintilla/cocoa -c $< -o $@

build/obj/boost/%.o: $(UP)/boostregex/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(SCI_INCLUDES) -c $< -o $@

build/obj/lex/src/%.o: $(UP)/lexilla/src/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

build/obj/lex/lib/%.o: $(UP)/lexilla/lexlib/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

build/obj/lex/lexers/%.o: $(UP)/lexilla/lexers/%.cxx
	@mkdir -p $(dir $@)
	$(CXX) $(THIRD_FLAGS) -fvisibility=hidden $(LEX_INCLUDES) -c $< -o $@

build/obj/app/%.o: src/%.mm
	@mkdir -p $(dir $@)
	$(CXX) $(OBJCXX) $(APP_INCLUDES) -c $< -o $@

build/obj/app/%.o: src/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -Wall -Wextra -Wno-unused-parameter -Isrc -c $< -o $@

build/obj/app/port_tests.o: tests/port_tests.mm
	@mkdir -p $(dir $@)
	$(CXX) $(OBJCXX) $(APP_INCLUDES) -c $< -o $@

$(APP)/Contents/MacOS/NotepadPlusPlus: $(APP_OBJ) $(ENGINE_OBJ)
	@mkdir -p $(dir $@)
	$(CXX) $(SYS) -fobjc-arc $^ -framework Cocoa -framework QuartzCore -framework CoreFoundation -framework WebKit -framework PDFKit -liconv -lz -o $@

build/port_tests: $(TEST_OBJ) $(ENGINE_OBJ)
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

ICON_SRC := resources/AppIcon.jpg
ICONSET := build/AppIcon.iconset

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
	cp $(UP)/PowerEditor/src/langs.model.xml $(APP)/Contents/Resources/langs.model.xml
	cp $(UP)/PowerEditor/src/stylers.model.xml $(APP)/Contents/Resources/stylers.model.xml
	sips -s format tiff $(UP)/scintilla/cocoa/res/mac_cursor_busy.png --out $(APP)/Contents/Resources/mac_cursor_busy.tiff >/dev/null
	sips -s format tiff $(UP)/scintilla/cocoa/res/mac_cursor_flipped.png --out $(APP)/Contents/Resources/mac_cursor_flipped.tiff >/dev/null

plugin: $(APP)/Contents/Info.plist
	@mkdir -p $(APP)/Contents/PlugIns
	$(CC) $(SYS) -dynamiclib -Isrc plugins/sample/SamplePlugin.c -o $(APP)/Contents/PlugIns/SamplePlugin.dylib
	$(CC) $(SYS) -dynamiclib -Isrc plugins/mimetools/MimeTools.c -o $(APP)/Contents/PlugIns/MimeTools.dylib
	$(CC) $(SYS) -dynamiclib -Isrc plugins/converter/Converter.c -o $(APP)/Contents/PlugIns/Converter.dylib
	$(CC) $(SYS) -fobjc-arc -dynamiclib -Isrc plugins/json/JsonTools.m -framework Foundation -o $(APP)/Contents/PlugIns/JsonTools.dylib

test: all
	./build/port_tests $(UP)/PowerEditor/src/langs.model.xml

clean:
	rm -rf build
