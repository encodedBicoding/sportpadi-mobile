# OpenAPI to Dart client

The contract between backend and app. The backend (`sportpadi-workspace`)
generates `openapi.json` from the tRPC procedures\' `.meta({ openapi })`; commit
it here, then generate the typed Dart client into `lib/data/api/generated/`.

## Recommended: swagger_parser (pure Dart, no Java)

```bash
dart pub global activate swagger_parser
swagger_parser            # reads swagger_parser.yaml
```

## Alternative: openapi-generator (dart-dio, needs Java)

```bash
openapi-generator generate -i openapi/openapi.json -g dart-dio -o packages/api_client
```

Keep the spec versioned and diff it in review — a breaking change should fail CI
until the client is regenerated and call sites are fixed.
