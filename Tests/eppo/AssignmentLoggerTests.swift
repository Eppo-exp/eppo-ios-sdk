import XCTest

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import EppoFlagging

final class AssignmentLoggerTests: XCTestCase {
   var loggerSpy: AssignmentLoggerSpy!
   var eppoClient: EppoClient!
   var UFCTestJSON: Data!

   override func setUpWithError() throws {
       try super.setUpWithError()

       // Reset the shared instance to avoid test interference
       EppoClient.resetSharedInstance()

       let fileURL = Bundle.module.url(
           forResource: "Resources/test-data/ufc/flags-v1-obfuscated.json",
           withExtension: ""
       )!
       UFCTestJSON = try! Data(contentsOf: fileURL)

       stub(condition: isHost("fscdn.eppo.cloud")) { _ in
           let stubData = self.UFCTestJSON!
           return HTTPStubsResponse(data: stubData, statusCode: 200, headers: ["Content-Type": "application/json"])
       }

       loggerSpy = AssignmentLoggerSpy()
   }

    // todo: do obfuscation and not tests.

   func testLogger() async throws {
       eppoClient = try await EppoClient.initialize(sdkKey: "mock-api-key", assignmentLogger: loggerSpy.logger, assignmentCache: nil)

       let assignment = eppoClient.getNumericAssignment(
           flagKey: "numeric_flag",
           subjectKey: "6255e1a72a84e984aed55668",
           subjectAttributes: SubjectAttributes(),
           defaultValue: 0)
       XCTAssertEqual(assignment, 3.1415926)
       
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertEqual(lastAssignment.allocation, "rollout")
           XCTAssertEqual(lastAssignment.experiment, "numeric_flag-rollout")
           XCTAssertEqual(lastAssignment.variation, "pi")
           XCTAssertEqual(lastAssignment.featureFlag, "numeric_flag")
           XCTAssertEqual(lastAssignment.subject, "6255e1a72a84e984aed55668")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }

   func testHoldoutLoggingWithEntityIdAndHoldoutInfo() async throws {
       // Create a test configuration with holdout information in extraLogging
       let testJsonString = """
       {
           "format": "SERVER",
           "createdAt": "2024-04-17T19:40:53.716Z",
           "environment": {
               "name": "Test"
           },
           "flags": {
               "boolean-flag": {
                   "key": "boolean-flag",
                   "enabled": true,
                   "variationType": "BOOLEAN",
                   "variations": {
                       "true": {
                           "key": "true",
                           "value": true
                       },
                       "false": {
                           "key": "false",
                           "value": false
                       }
                   },
                   "totalShards": 10000,
                   "entityId": 1,
                   "allocations": [
                       {
                           "key": "allocation-84-short-term-holdout",
                           "startAt": "2025-07-18T20:09:55.084Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "false",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-84-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 10000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-traffic",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 1000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 5000
                                               }
                                           ]
                                       }
                                   ],
                                   "extraLogging": {
                                       "holdoutKey": "short-term-holdout",
                                       "holdoutVariation": "status_quo"
                                   }
                               },
                               {
                                   "variationKey": "true",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-84-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 10000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-traffic",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 1000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-split",
                                           "ranges": [
                                               {
                                                   "start": 5000,
                                                   "end": 10000
                                               }
                                           ]
                                       }
                                   ],
                                   "extraLogging": {
                                       "holdoutKey": "short-term-holdout",
                                       "holdoutVariation": "all_shipped"
                                   }
                               }
                           ],
                           "doLog": true
                       },
                       {
                           "key": "allocation-84",
                           "startAt": "2025-07-18T20:09:55.084Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "true",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-84-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 10000
                                               }
                                           ]
                                       }
                                   ]
                               }
                           ],
                           "doLog": true
                       },
                       {
                           "key": "allocation-81",
                           "startAt": "2025-07-18T20:04:55.586Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "false",
                                   "shards": []
                               }
                           ],
                           "doLog": true
                       }
                   ]
               }
           }
       }
       """

       eppoClient = EppoClient.initializeOffline(
           sdkKey: "mock-api-key",
           assignmentLogger: loggerSpy.logger,
           assignmentCache: nil,
           initialConfiguration: try Configuration(
               flagsConfigurationJson: Data(testJsonString.utf8),
               obfuscated: false
           )
       )

       let _ = eppoClient.getBooleanAssignment(
           flagKey: "boolean-flag",
           subjectKey: "test-subject-9",
           subjectAttributes: SubjectAttributes(),
           defaultValue: false
       )

       // Verify the assignment was logged with holdout information
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertEqual(lastAssignment.entityId, 1)
           XCTAssertEqual(lastAssignment.extraLogging, ["holdoutKey": "short-term-holdout", "holdoutVariation": "status_quo"])
           XCTAssertEqual(lastAssignment.featureFlag, "boolean-flag")
           XCTAssertEqual(lastAssignment.allocation, "allocation-84-short-term-holdout")
           XCTAssertEqual(lastAssignment.variation, "false")
           XCTAssertEqual(lastAssignment.subject, "test-subject-9")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }

   func testHoldoutLoggingWithoutEntityIdNorHoldoutInfo() async throws {
       // Create a test configuration with entityId but without holdout information
       let testJsonString = """
       {
           "format": "SERVER",
           "createdAt": "2024-04-17T19:40:53.716Z",
           "environment": {
               "name": "Test"
           },
           "flags": {
               "boolean-flag": {
                   "key": "boolean-flag",
                   "enabled": true,
                   "variationType": "BOOLEAN",
                   "variations": {
                       "true": {
                           "key": "true",
                           "value": true
                       },
                       "false": {
                           "key": "false",
                           "value": false
                       }
                   },
                   "totalShards": 10000,
                   "allocations": [
                       {
                           "key": "allocation-83-holdout-short-term-holdout",
                           "startAt": "2025-07-18T20:05:12.927Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "false",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-83-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 5000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-traffic",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 1000
                                               }
                                           ]
                                       }
                                   ]
                               },
                               {
                                   "variationKey": "false",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-83-split",
                                           "ranges": [
                                               {
                                                   "start": 5000,
                                                   "end": 10000
                                               }
                                           ]
                                       },
                                       {
                                           "salt": "short-term-holdout-holdout-traffic",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 1000
                                               }
                                           ]
                                       }
                                   ]
                               }
                           ],
                           "doLog": true
                       },
                       {
                           "key": "allocation-83",
                           "startAt": "2025-07-18T20:05:12.927Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "true",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-83-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 5000
                                               }
                                           ]
                                       }
                                   ]
                               },
                               {
                                   "variationKey": "false",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-83-split",
                                           "ranges": [
                                               {
                                                   "start": 5000,
                                                   "end": 10000
                                               }
                                           ]
                                       }
                                   ]
                               }
                           ],
                           "doLog": true
                       },
                       {
                           "key": "allocation-81",
                           "startAt": "2025-07-18T20:04:55.586Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "false",
                                   "shards": []
                               }
                           ],
                           "doLog": true
                       }
                   ]
               }
           }
       }
       """

       eppoClient = EppoClient.initializeOffline(
           sdkKey: "mock-api-key",
           assignmentLogger: loggerSpy.logger,
           assignmentCache: nil,
           initialConfiguration: try Configuration(
               flagsConfigurationJson: Data(testJsonString.utf8),
               obfuscated: false
           )
       )

       let _ = eppoClient.getBooleanAssignment(
           flagKey: "boolean-flag",
           subjectKey: "test-subject-9",
           subjectAttributes: SubjectAttributes(),
           defaultValue: false
       )

       // Verify the assignment was from a holdout, logged with entityId, but has no holdout information because
       XCTAssertTrue(loggerSpy.wasCalled)
       if let lastAssignment = loggerSpy.lastAssignment {
           XCTAssertTrue(lastAssignment.extraLogging.isEmpty)
           XCTAssertNil(lastAssignment.entityId)
           XCTAssertEqual(lastAssignment.featureFlag, "boolean-flag")
           XCTAssertEqual(lastAssignment.allocation, "allocation-83-holdout-short-term-holdout")
           XCTAssertEqual(lastAssignment.variation, "false")
           XCTAssertEqual(lastAssignment.subject, "test-subject-9")
       } else {
           XCTFail("No last assignment was logged.")
       }
   }

   func testHoldoutLoggingWithDoLogFalse() async throws {
       // Create a test configuration with doLog: false
       let testJsonString = """
       {
           "format": "SERVER",
           "createdAt": "2024-04-17T19:40:53.716Z",
           "environment": {
               "name": "Test"
           },
           "flags": {
               "boolean-flag": {
                   "key": "boolean-flag",
                   "enabled": true,
                   "variationType": "BOOLEAN",
                   "variations": {
                       "true": {
                           "key": "true",
                           "value": true
                       },
                       "false": {
                           "key": "false",
                           "value": false
                       }
                   },
                   "totalShards": 10000,
                   "allocations": [
                       {
                           "key": "allocation-no-logging",
                           "startAt": "2025-07-18T20:09:55.084Z",
                           "endAt": "9999-12-31T00:00:00.000Z",
                           "splits": [
                               {
                                   "variationKey": "true",
                                   "shards": [
                                       {
                                           "salt": "boolean-flag-no-logging-split",
                                           "ranges": [
                                               {
                                                   "start": 0,
                                                   "end": 10000
                                               }
                                           ]
                                       }
                                   ]
                               }
                           ],
                           "doLog": false
                       }
                   ]
               }
           }
       }
       """

       eppoClient = EppoClient.initializeOffline(
           sdkKey: "mock-api-key",
           assignmentLogger: loggerSpy.logger,
           assignmentCache: nil,
           initialConfiguration: try Configuration(
               flagsConfigurationJson: Data(testJsonString.utf8),
               obfuscated: false
           )
       )

       let _ = eppoClient.getBooleanAssignment(
           flagKey: "boolean-flag",
           subjectKey: "test-subject-no-logging",
           subjectAttributes: SubjectAttributes(),
           defaultValue: false
       )

       // Verify the assignment was NOT logged because doLog: false
       XCTAssertFalse(loggerSpy.wasCalled)
       XCTAssertNil(loggerSpy.lastAssignment)
   }

    func testHoldoutLoggingWithObfuscatedExtraLogging() async throws {
        // Create a test configuration with fully obfuscated data
        // Flag key "boolean-flag" -> MD5 hash
        // Variation keys "true"/"false" -> base64 encoded
        // Allocation key "allocation-84-short-term-holdout" -> base64 encoded
        // Salt "boolean-flag-84-split" -> base64 encoded
        // extraLogging keys and values -> base64 encoded
        let testJsonString = """
        {
            "format": "CLIENT",
            "createdAt": "2024-04-17T19:40:53.716Z",
            "environment": {
                "name": "Test"
            },
            "flags": {
                "da342f2d2df9aa65fd422191c581d4dc": {
                    "key": "da342f2d2df9aa65fd422191c581d4dc",
                    "enabled": true,
                    "variationType": "BOOLEAN",
                    "variations": {
                        "dHJ1ZQ==": {
                            "key": "dHJ1ZQ==",
                            "value": "dHJ1ZQ=="
                        },
                        "ZmFsc2U=": {
                            "key": "ZmFsc2U=",
                            "value": "ZmFsc2U="
                        }
                    },
                    "totalShards": 10000,
                    "entityId": 1,
                    "allocations": [
                        {
                            "key": "YWxsb2NhdGlvbi04NC1zaG9ydC10ZXJtLWhvbGRvdXQ=",
                            "startAt": "MjAyNS0wNy0xOFQyMDowOTo1NS4wODRa",
                            "endAt": "OTk5OS0xMi0zMVQwMDowMDowMC4wMDBa",
                            "splits": [
                                {
                                    "variationKey": "ZmFsc2U=",
                                    "shards": [
                                        {
                                            "salt": "Ym9vbGVhbi1mbGFnLTg0LXNwbGl0",
                                            "ranges": [
                                                {
                                                    "start": 0,
                                                    "end": 10000
                                                }
                                            ]
                                        }
                                    ],
                                    "extraLogging": {
                                        "aG9sZG91dEtleQ==": "c2hvcnQtdGVybS1ob2xkb3V0",
                                        "aG9sZG91dFZhcmlhdGlvbg==": "c3RhdHVzX3F1bw=="
                                    }
                                }
                            ],
                            "doLog": true
                        }
                    ]
                }
            }
        }
        """

        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy.logger,
            assignmentCache: nil,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: true
            )
        )

        let _ = eppoClient.getBooleanAssignment(
            flagKey: "boolean-flag",
            subjectKey: "test-subject-9",
            subjectAttributes: SubjectAttributes(),
            defaultValue: false
        )

        // Verify the assignment was logged with unobfuscated holdout information
        XCTAssertTrue(loggerSpy.wasCalled)
        if let lastAssignment = loggerSpy.lastAssignment {
            XCTAssertEqual(lastAssignment.entityId, 1)
            XCTAssertEqual(lastAssignment.extraLogging, ["holdoutKey": "short-term-holdout", "holdoutVariation": "status_quo"])
            XCTAssertEqual(lastAssignment.featureFlag, "boolean-flag")
            XCTAssertEqual(lastAssignment.allocation, "allocation-84-short-term-holdout")
            XCTAssertEqual(lastAssignment.variation, "false")
            XCTAssertEqual(lastAssignment.subject, "test-subject-9")
        } else {
            XCTFail("No last assignment was logged.")
        }
    }

    func testHoldoutLoggingWithMixedObfuscatedExtraLogging() async throws {
        // Create a test configuration with mixed obfuscation scenarios
        let testJsonString = """
        {
            "format": "CLIENT",
            "createdAt": "2024-04-17T19:40:53.716Z",
            "environment": {
                "name": "Test"
            },
            "flags": {
                "da342f2d2df9aa65fd422191c581d4dc": {
                    "key": "da342f2d2df9aa65fd422191c581d4dc",
                    "enabled": true,
                    "variationType": "BOOLEAN",
                    "variations": {
                        "dHJ1ZQ==": {
                            "key": "dHJ1ZQ==",
                            "value": "dHJ1ZQ=="
                        },
                        "ZmFsc2U=": {
                            "key": "ZmFsc2U=",
                            "value": "ZmFsc2U="
                        }
                    },
                    "totalShards": 10000,
                    "allocations": [
                        {
                            "key": "YWxsb2NhdGlvbi04NS1taXhlZC1ob2xkb3V0",
                            "startAt": "MjAyNS0wNy0xOFQyMDowOTo1NS4wODRa",
                            "endAt": "OTk5OS0xMi0zMVQwMDowMDowMC4wMDBa",
                            "splits": [
                                {
                                    "variationKey": "ZmFsc2U=",
                                    "shards": [
                                        {
                                            "salt": "Ym9vbGVhbi1mbGFnLTg1LXNwbGl0",
                                            "ranges": [
                                                {
                                                    "start": 0,
                                                    "end": 10000
                                                }
                                            ]
                                        }
                                    ],
                                    "extraLogging": {
                                        "aG9sZG91dEtleQ==": "c2hvcnQtdGVybS1ob2xkb3V0",
                                        "bm9ybWFsS2V5": "bm9ybWFsVmFsdWU=",
                                        "aG9sZG91dFZhcmlhdGlvbg==": "c3RhdHVzX3F1bw=="
                                    }
                                }
                            ],
                            "doLog": true
                        }
                    ]
                }
            }
        }
        """

        eppoClient = EppoClient.initializeOffline(
            sdkKey: "mock-api-key",
            assignmentLogger: loggerSpy.logger,
            assignmentCache: nil,
            initialConfiguration: try Configuration(
                flagsConfigurationJson: Data(testJsonString.utf8),
                obfuscated: true
            )
        )

        let _ = eppoClient.getBooleanAssignment(
            flagKey: "boolean-flag",
            subjectKey: "test-subject-10",
            subjectAttributes: SubjectAttributes(),
            defaultValue: false
        )

        // Verify the assignment was logged with properly decoded extraLogging
        XCTAssertTrue(loggerSpy.wasCalled)
        if let lastAssignment = loggerSpy.lastAssignment {
            XCTAssertEqual(lastAssignment.extraLogging, [
                "holdoutKey": "short-term-holdout",
                "normalKey": "normalValue",
                "holdoutVariation": "status_quo"
            ])
            XCTAssertEqual(lastAssignment.featureFlag, "boolean-flag")
            XCTAssertEqual(lastAssignment.allocation, "allocation-85-mixed-holdout")
            XCTAssertEqual(lastAssignment.variation, "false")
            XCTAssertEqual(lastAssignment.subject, "test-subject-10")
        } else {
            XCTFail("No last assignment was logged.")
        }
    }
}
