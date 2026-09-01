# sportpadi-mobile — common tasks
FLAVOR ?= dev
BASE ?= http://10.0.2.2:3000   # Android emulator -> host localhost

.PHONY: get run run-ios gen watch clean api-client

get:
	flutter pub get

run:
	flutter run -t lib/main_$(FLAVOR).dart --dart-define=API_BASE_URL=$(BASE)

run-ios:
	flutter run -t lib/main_$(FLAVOR).dart --dart-define=API_BASE_URL=http://localhost:3000

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
