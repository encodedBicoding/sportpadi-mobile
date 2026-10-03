# sportpadi-mobile — common tasks
FLAVOR ?= dev
BASE ?= http://10.0.2.2:3000   # Android emulator -> host localhost

.PHONY: get run run-ios run-device gen watch clean api-client

get:
	flutter pub get

run:
	flutter run -t lib/main_$(FLAVOR).dart --dart-define=API_BASE_URL=$(BASE)

run-ios:
	flutter run -t lib/main_$(FLAVOR).dart --dart-define=API_BASE_URL=http://localhost:3000

# A REAL phone on the same Wi-Fi: points the app at this Mac's CURRENT LAN
# address (it changes when the router hands out a new one), so a stale
# --dart-define never leaves sign-in timing out. Pick a phone with
# `make run-device DEVICE=<id>` (ids from `flutter devices`).
run-device:
	@IP=$$(ipconfig getifaddr en0 || ipconfig getifaddr en1); \
	if [ -z "$$IP" ]; then echo "No Wi-Fi/LAN address found on en0/en1"; exit 1; fi; \
	echo "API_BASE_URL=http://$$IP:3000"; \
	flutter run $(if $(DEVICE),-d $(DEVICE),) -t lib/main_$(FLAVOR).dart --dart-define=API_BASE_URL=http://$$IP:3000

gen:
	dart run build_runner build --delete-conflicting-outputs

watch:
	dart run build_runner watch --delete-conflicting-outputs

api-client:
	# Regenerate the typed API client from the committed OpenAPI spec.
	# Requires: dart pub global activate swagger_parser
	swagger_parser

clean:
	flutter clean && flutter pub get
