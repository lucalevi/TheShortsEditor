APP := build/Build/Products/Debug/Shorts Editor.app

.PHONY: project open build run test clean

project:            ## Generate TheShortsEditor.xcodeproj from project.yml
	xcodegen generate --quiet

open: project       ## Open the project in Xcode
	open TheShortsEditor.xcodeproj

build: project      ## Build the Debug app into ./build
	xcodebuild -project TheShortsEditor.xcodeproj -scheme TheShortsEditor -configuration Debug \
		-derivedDataPath build -quiet build

run: build          ## Build and launch the app
	open "$(APP)"

test:               ## Run the EditorCore and RenderEngine tests
	cd Packages/EditorCore && swift test

clean:
	rm -rf build Packages/EditorCore/.build
