###--- Shared variables ---###
# Browser type (browser, but "chrome-mv3" becomes "chrome").
BROWSER_TYPE = $(browser)
ifeq ('$(browser)','chrome-mv3')
  BROWSER_TYPE = chrome
endif

# Output directory for builds.
BUILD_DIR = build/$(browser)/$(type)
ifeq ($(browser),test)
  BUILD_DIR := build/test
endif


###--- Top level targets ---###
# TODO:
#  - Add default `help` target.
#  - Set browser/type automatically where possible.
#  - Add check that browser+type are set when necessary.

## release: Create a release build for a platform in build/$(browser)/release
## specify browser=(chrome|chrome-mv3|firefox) type=release
release: clean npm copy build

.PHONY: release

## chrome-mv3-beta: Create a beta Chrome MV3 build in build/$(browser)/release
## specify browser=chrome-mv3 type=release
chrome-mv3-beta: release chrome-mv3-beta-zip

.PHONY: chrome-mv3-beta

## beta-firefox: Create a beta Firefox build in build/$(browser)/release
## specify browser=firefox type=release
beta-firefox: release beta-firefox-zip

.PHONY: beta-firefox

## dev: Create a debug build for a platform in build/$(browser)/dev.
## specify browser=(chrome|chrome-mv3|firefox) type=dev
dev: copy build

.PHONY: dev

## watch: Create a debug build for a platform in build/$(browser)/dev, and keep
##        it up to date as files are changed.
## specify browser=(chrome|chrome-mv3|firefox) type=dev
MAKE = make -j4 $(type) browser=$(browser) type=$(type)
watch:
	$(MAKE)
	@echo "\n** Build ready -  Watching for changes **\n"
	while true; do $(MAKE) -q --silent || $(MAKE); sleep 1; done

.PHONY: watch

## unit-test: Run the unit tests.
unit-test: build/test/background.js build/test/ui.js build/test/shared-utils.js
	node_modules/.bin/karma start karma.conf.js

.PHONY: unit-test

## test-int: Run legacy integration tests against the Chrome MV2 extension.
test-int: integration-test/artifacts/attribution.json
	make dev browser=chrome type=dev
	jasmine --config=integration-test/config.json

.PHONY: test-int

## test-int-mv3: Run legacy integration tests against the Chrome MV3 extension.
test-int-mv3: integration-test/artifacts/attribution.json
	make dev browser=chrome-mv3 type=dev
	jasmine --config=integration-test/config-mv3.json

.PHONY: test-int-mv3

## npm: Pull in the external dependencies (npm install).
npm:
	npm ci --ignore-scripts
	npm rebuild puppeteer

.PHONY: npm

## clean: Clear the builds and temporary files.
clean:
	rm -f shared/data/smarter_encryption.txt shared/data/bundled/smarter-encryption-rules.json integration-test/artifacts/attribution.json:
	rm -rf $(BUILD_DIR)

.PHONY: clean


###--- Release packaging ---###
chrome-release-zip:
	rm -f build/chrome/release/chrome-release-*.zip
	cd build/chrome/release/ && zip -rq chrome-release-$(shell date +"%Y%m%d_%H%M%S").zip *

.PHONY: chrome-release-zip

chrome-mv3-release-zip:
	rm -f build/chrome-mv3/release/chrome-mv3-release-*.zip
	cd build/chrome-mv3/release/ && zip -rq chrome-mv3-release-$(shell date +"%Y%m%d_%H%M%S").zip *

.PHONY: chrome-mv3-release-zip

chrome-mv3-beta-zip: prepare-chrome-beta chrome-mv3-release-zip
	

.PHONY: chrome-mv3-beta-zip

prepare-chrome-beta:
	sed 's/__MSG_appName__/DuckDuckGo Privacy Essentials MV3 Beta/' ./browsers/chrome-mv3/manifest.json > build/chrome-mv3/release/manifest.json
	cp -r build/chrome-mv3/release/img/beta/* build/chrome-mv3/release/img/

.PHONY: prepare-chrome-beta

remove-firefox-id:
	sed '/jid1-ZAdIEUB7XOzOJw@jetpack/d' ./browsers/firefox/manifest.json > build/firefox/release/manifest.json

.PHONY: remove-firefox-id

beta-firefox-zip: remove-firefox-id
	cd build/firefox/release/ && web-ext build

.PHONY: beta-firefox-zip


###--- Integration test setup ---###
# Artifacts produced by the integration tests.
setup-artifacts-dir:
	rm -rf integration-test/artifacts
	mkdir -p integration-test/artifacts/screenshots
	mkdir -p integration-test/artifacts/api_schemas

.PHONY: setup-artifacts-dir

# Fetch integration test data.
integration-test/artifacts/attribution.json: node_modules/privacy-test-pages/adClickFlow/shared/testCases.json setup-artifacts-dir
	mkdir -p integration-test/artifacts
	cp $< $@


###--- Copy targets ---###
COPY_TARGETS =

define copy-dir
  $1_TARGETS = $(patsubst $1%,$2%,$(shell find $1 -type f -not -name "*~" -not -name "smarter_encryption.txt"))
  COPY_TARGETS += $$($1_TARGETS)
  $$($1_TARGETS): $2%: $1%
	@mkdir -p $$(dir $$@)
	cp $$< $$@
endef

define copy-file
  COPY_TARGETS += $2
  $2: $1
	@mkdir -p $$(dir $$@)
	cp $$< $$@
endef

# Copy files from directories.
$(eval $(call copy-dir,./browsers/$(browser),$(BUILD_DIR)))
ifneq ("$(browser)","chrome")
  $(eval $(call copy-dir,./browsers/chrome/_locales,$(BUILD_DIR)/_locales))
endif
$(eval $(call copy-dir,shared/data,$(BUILD_DIR)/data))
$(eval $(call copy-dir,shared/html,$(BUILD_DIR)/html))
$(eval $(call copy-dir,shared/img,$(BUILD_DIR)/img))
$(eval $(call copy-dir,node_modules/@duckduckgo/privacy-dashboard/build/app,$(BUILD_DIR)/dashboard))
$(eval $(call copy-dir,shared/font,$(BUILD_DIR)/public/font))
$(eval $(call copy-dir,node_modules/@duckduckgo/tracker-surrogates/surrogates,$(BUILD_DIR)/web_accessible_resources))

# Copy specific files.
$(eval $(call copy-file,shared/js/content-scripts/content-scope-messaging.js,$(BUILD_DIR)/public/js/content-scripts/content-scope-messaging.js))
$(eval $(call copy-file,node_modules/@duckduckgo/autofill/dist/autofill.js,$(BUILD_DIR)/public/js/content-scripts/autofill.js))
$(eval $(call copy-file,node_modules/@duckduckgo/autofill/dist/autofill-debug.js,$(BUILD_DIR)/public/js/content-scripts/autofill-debug.js))
$(eval $(call copy-file,node_modules/@duckduckgo/autofill/dist/autofill.css,$(BUILD_DIR)/public/css/autofill.css))
$(eval $(call copy-file,node_modules/@duckduckgo/autofill/dist/autofill-host-styles_$(BROWSER_TYPE).css,$(BUILD_DIR)/public/css/autofill-host-styles.css))

copy: $(COPY_TARGETS)

.PHONY: copy


###--- Build targets ---###
## Figure out the correct Browserify command for bundling.
# TODO: Switch to a better bundler.
# Workaround Browserify not following symlinks in --only.
BROWSERIFY_GLOBAL_TARGETS = ./node_modules/@duckduckgo
BROWSERIFY_GLOBAL_TARGETS += $(shell find node_modules/@duckduckgo/ -maxdepth 1 -type l | xargs -n1 readlink -f)

BROWSERIFY_BIN = node_modules/.bin/browserify
BROWSERIFY = $(BROWSERIFY_BIN) -t babelify -t [ babelify --global  --only [ $(BROWSERIFY_GLOBAL_TARGETS) ] --presets [ @babel/preset-env ] ]
# Ensure sourcemaps are included for the bundles during development.
ifeq ($(type),dev)
  BROWSERIFY += -d
endif

## All source files that potentially need to be bundled.
# TODO: Use automatic dependency generation (e.g. `browserify --list`) for
#       the bundling targets instead?
WATCHED_FILES = $(shell find -L shared packages/ unit-test/ -type f -not -path "packages/*/node_modules/*" -not -name "*~")
# If the node_modules/@duckduckgo/ directory exists, include those source files
# in the list too.
ifneq ("$(wildcard node_modules/@duckduckgo/)","")
  WATCHED_FILES += $(shell find -L node_modules/@duckduckgo/ -type f -not -path "node_modules/@duckduckgo/*/.git/*" -not -path "node_modules/@duckduckgo/*/node_modules/*" -not -name "*~")
endif

## Extension background/serviceworker script.
BACKGROUND_JS = shared/js/background/background.js
ifeq ($(type), dev)
  BACKGROUND_JS := shared/js/background/debug.js $(BACKGROUND_JS)
endif
$(BUILD_DIR)/public/js/background.js: $(WATCHED_FILES)
	$(BROWSERIFY) $(BACKGROUND_JS) -o $@

## Extension UI/Devtools scripts.
$(BUILD_DIR)/public/js/base.js: $(WATCHED_FILES)
	mkdir -p `dirname $@`
	$(BROWSERIFY) shared/js/ui/base/index.js > $@

$(BUILD_DIR)/public/js/feedback.js: $(WATCHED_FILES)
	$(BROWSERIFY) shared/js/ui/pages/feedback.js > $@

$(BUILD_DIR)/public/js/options.js: $(WATCHED_FILES)
	$(BROWSERIFY) shared/js/ui/pages/options.js > $@

$(BUILD_DIR)/public/js/devtools-panel.js: $(WATCHED_FILES)
	$(BROWSERIFY) shared/js/devtools/panel.js > $@

$(BUILD_DIR)/public/js/list-editor.js: $(WATCHED_FILES)
	$(BROWSERIFY) shared/js/devtools/list-editor.js > $@

$(BUILD_DIR)/public/js/newtab.js: $(WATCHED_FILES)
	$(BROWSERIFY) shared/js/newtab/newtab.js > $@

JS_BUNDLES = background.js base.js feedback.js options.js devtools-panel.js list-editor.js newtab.js

BUILD_TARGETS = $(addprefix $(BUILD_DIR)/public/js/, $(JS_BUNDLES))

## Unit tests scripts.
UNIT_TEST_SRC = unit-test/background/*.js unit-test/background/classes/*.js unit-test/background/events/*.js unit-test/background/storage/*.js unit-test/background/reference-tests/*.js
build/test:
	mkdir -p $@

build/test/background.js: $(TEST_FILES) $(WATCHED_FILES) | build/test
	$(BROWSERIFY) -t brfs -t ./scripts/browserifyFileMapTransform $(UNIT_TEST_SRC) -o $@

build/test/ui.js: $(TEST_FILES) | build/test
	$(BROWSERIFY) shared/js/ui/base/index.js unit-test/ui/**/*.js -o $@

build/test/shared-utils.js: $(TEST_FILES) | build/test
	$(BROWSERIFY) unit-test/shared-utils/*.js -o $@

## Content Scope Scripts
shared/data/bundled/tracker-lookup.json:
	node scripts/bundleTrackers.mjs

# Rebuild content-scope-scripts if it's a local checkout (.git is present), but
# not otherwise. That is important, since content-scope-scripts releases often
# have newer source files than build files.
CONTENT_SCOPE_SCRIPTS_DEPS =
ifneq ("$(wildcard node_modules/@duckduckgo/content-scope-scripts/.git/)","")
  CONTENT_SCOPE_SCRIPTS_DEPS += $(shell find node_modules/@duckduckgo/content-scope-scripts/src/ node_modules/@duckduckgo/content-scope-scripts/inject/ node_modules/@duckduckgo/content-scope-scripts/package.json -type f -not -name "*~")
  CONTENT_SCOPE_SCRIPTS_DEPS += node_modules/@duckduckgo/content-scope-scripts/node_modules
endif

node_modules/@duckduckgo/content-scope-scripts/node_modules:
	cd node_modules/@duckduckgo/content-scope-scripts; npm install

node_modules/@duckduckgo/content-scope-scripts/build/$(browser)/inject.js: $(CONTENT_SCOPE_SCRIPTS_DEPS)
	cd node_modules/@duckduckgo/content-scope-scripts; npm run build-$(browser)

$(BUILD_DIR)/public/js/inject.js: node_modules/@duckduckgo/content-scope-scripts/build/$(browser)/inject.js shared/data/bundled/tracker-lookup.json shared/data/bundled/extension-config.json
	node scripts/bundleContentScopeScripts.mjs $@ $^

BUILD_TARGETS += $(BUILD_DIR)/public/js/inject.js

## SASS
SASS = node_modules/.bin/sass
SCSS_SOURCE = $(shell find shared/scss/ -type f)
OUTPUT_CSS_FILES = $(BUILD_DIR)/public/css/noatb.css $(BUILD_DIR)/public/css/options.css $(BUILD_DIR)/public/css/feedback.css
$(BUILD_DIR)/public/css/base.css: shared/scss/base/base.scss $(SCSS_SOURCE)
	$(SASS) $< $@
$(BUILD_DIR)/public/css/%.css: shared/scss/%.scss $(SCSS_SOURCE)
	$(SASS) $< $@

BUILD_TARGETS += $(BUILD_DIR)/public/css/base.css $(OUTPUT_CSS_FILES)

## Other

# Fetch Smarter Encryption data for bundled Smarter Encryption
# declarativeNetRequest rules.
shared/data/smarter_encryption.txt:
	curl https://staticcdn.duckduckgo.com/https/smarter_encryption.txt.gz | gunzip -c > shared/data/smarter_encryption.txt

# Generate Smarter Encryption declarativeNetRequest rules for MV3 builds.
$(BUILD_DIR)/data/bundled/smarter-encryption-rules.json: shared/data/smarter_encryption.txt
	mkdir -p `dirname $@`
	npx ddg2dnr smarter-encryption $< $@

ifeq ('$(browser)','chrome-mv3')
  BUILD_TARGETS += $(BUILD_DIR)/data/bundled/smarter-encryption-rules.json
endif

$(BUILD_DIR)/data/surrogates.txt: $(node_modules/@duckduckgo/tracker-surrogates/surrogates_TARGETS)
	node scripts/generateListOfSurrogates.js -i $(dir $<) > $@

BUILD_TARGETS += $(BUILD_DIR)/data/surrogates.txt

build: $(BUILD_TARGETS)

.PHONY: build
