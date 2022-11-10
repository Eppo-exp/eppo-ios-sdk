# eppo-flagging

iOS implementation of the Eppo Randomization and Feature Flagging SDK.

To add the Eppo iOS SDK to a project, choose File > Add Packages... in Xcode. Click Add Local... and choose this directory. This will add two targets to your project:

* eppo-flagging
* eppo-flagging-tests

Then select the eppo-flagging-tests target in Xcode and run Product > Test.

##Updating Test Data

Test data is stored online. To ensure you have the most up to date data:

First install [gsutil](https://cloud.google.com/storage/docs/gsutil_install) and update test data using

  make test-data
