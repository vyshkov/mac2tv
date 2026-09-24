.PHONY: all build release app run clean

all: app

build:
	swift build

release:
	swift build -c release

app:
	./scripts/package_app.sh

run: app
	open MKVAirPlay.app

clean:
	swift package clean
	rm -rf MKVAirPlay.app .build
