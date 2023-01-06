# Eppo iOS Feature Flagging SDK

iOS implementation of the Eppo Randomization and Feature Flagging SDK.

## Integrating the SDK

https://docs.geteppo.com/feature-flags/sdks/client-sdks/ios/

## Contributing

Periodically it may be necessary to fetch new test data. This is almost never necessary but useful if global test data has been updated.

First install [gsutil](https://cloud.google.com/storage/docs/gsutil_install) and update test data using

  make test-data

This is only necessary when test data has changed
