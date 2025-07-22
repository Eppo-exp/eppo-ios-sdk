# Eppo iOS (Swift) SDK

[![Test and lint SDK](https://github.com/Eppo-exp/eppo-ios-sdk/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/Eppo-exp/eppo-ios-sdk/actions/workflows/unit-tests.yml)

[Eppo](https://www.geteppo.com/) is a modular flagging and experimentation analysis tool. Eppo's iOS SDK is built to make assignments for single user client applications. Before proceeding you'll need an Eppo account.

The [primary documentation](https://docs.geteppo.com/sdks/client-sdks/ios/) explains the overall architecture and in-depth usage guides.

## Features

- Feature gates
- Kill switches
- Progressive rollouts
- A/B/n experiments
- Mutually exclusive experiments (Layers)
- Dynamic configuration

## Installation

While in XCode:

1. Choose `Package Dependencies`
2. Click `+` and enter package URL: `git@github.com:Eppo-exp/eppo-ios-sdk.git`
3. Set dependency rule to `Up to Next Minor Version` and select `Add Package`
4. Add to your project's target.

## Quick start

Begin by initializing Eppo's client; it is internally a singleton. It configures itself and performs a network request to fetch the latest flag configurations. 

Once initialized, the client can be used to make assignments anywhere in your app.

#### Initialize once

It is recommended to wrap initialization in a `Task` block in order to perform network request asynchronously.

```swift
Task {
    try await EppoClient.initialize(sdkKey: "SDK-KEY-FROM-DASHBOARD");
}
```

Optionally, you can pass in a pre-fetched configuration JSON string.

```swift
Task {
    try await EppoClient.initialize(
        sdkKey: "SDK-KEY-FROM-DASHBOARD",
        initialConfiguration: try Configuration(
            flagsConfigurationJson: Data(#"{ "pre-loaded-JSON": "passed in here" }"#.utf8),
            obfuscated: false
        )
    );
}

In both cases the SDK will perform a network request to fetch the latest flag configurations.

#### Offline initialization

If you'd like to initialize Eppo's client without performing a network request, you can pass in a pre-fetched configuration JSON string.

```swift
try EppoClient.initializeOffline(
    sdkKey: "SDK-KEY-FROM-DASHBOARD",
    initialConfiguration: try Configuration(
        flagsConfigurationJson: Data(#"{ "pre-loaded-JSON": "passed in here" }"#.utf8),
        obfuscated: false
    )
);
```

The `obfuscated` parameter is used to inform the SDK if the flag configuration is obfuscated.

The initialization method is synchronous and allows you to perform assignments immediately.

#### (Optional) Fetching the configuration from the remote source on-demand.**

After the client has been initialized, you can use `load()` to asynchronously fetch the latest flag configuration from the remote source.

```swift
try EppoClient.initializeOffline(
    sdkKey: "SDK-KEY-FROM-DASHBOARD",
    initialConfiguration: try Configuration(
        flagsConfigurationJson: Data(#"{ "pre-loaded-JSON": "passed in here" }"#.utf8),
        obfuscated: false
    )
);

...

Task {
    try await EppoClient.shared().load();
}
```

As modern iOS devices have substantial memory, applications are often kept in memory across sessions. This means that the flag configurations are not automatically reloaded on subsequent launches.

It is recommended to use the `load()` method to fetch the latest flag configurations when the application is launched.

#### Assign anywhere

Assignment is a synchronous operation.

```swift
let assignment = eppoClient.getStringAssignment(
    flagKey: "new-user-onboarding",
    subjectKey: user.id,
    subjectAttributes: user.attributes,
    defaultValue: "control"
);
```

For applications wrapping assignment in an `ObservableObject` is the best practice. This will create an object that will update Swift UI when the assignment is received.

```swift
@MainActor
public class AssignmentObserver: ObservableObject {
    @Published var assignment: String?

    public init() {
        do {
            // Use the shared instance after it has been configured.
            self.assignment = try EppoClient.shared().getStringAssignment(
                flagKey: "new-user-onboarding",
                subjectKey: user.id,
                subjectAttributes: user.attributes,
                defaultValue: "control"
            );
        } catch {
            self.assignment = nil
        }
    }
}
```

You can also choose to combinate instantiation and assignment within the same `ObservableObject`; the internal state will ensure only a single object and network request is created.

```swift
@MainActor
public class AssignmentObserver: ObservableObject {
    @Published var assignment: String?

    public init() {
        Task {
            do {
                // The initialization method has controls to maintain a single instance.
                try await EppoClient.initialize(sdkKey: "SDK-KEY-FROM-DASHBOARD");
                self.assignment = try EppoClient.shared().getStringAssignment(
                    flagKey: "new-user-onboarding",
                    subjectKey: user.id,
                    subjectAttributes: user.attributes,
                    defaultValue: "control"
                );
            } catch {
                self.assignment = nil
            }
        }
    }
}
```

Rendering the view:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var observer = AssignmentObserver()

    var body: some View {
        VStack {
            if let assignment = observer.assignment {
                Text("Assignment: \(assignment)")
                    .font(.headline)
                    .padding()
            } else {
                Text("Loading assignment...")
                    .font(.subheadline)
                    .padding()
            }
        }
        .onAppear {
            // You can perform additional actions on appear if needed
        }
    }
}
```

## Assignment functions

Every Eppo flag has a return type that is set once on creation in the dashboard. Once a flag is created, assignments in code should be made using the corresponding typed function: 

```
getBooleanAssignment(...)
getNumericAssignment(...)
getIntegerAssignment(...)
getStringAssignment(...)
getJSONStringAssignment(...)
```

Each function has the same signature, but returns the type in the function name. For booleans use `getBooleanAssignment`, which has the following signature:

```
func getBooleanAssignment(
  flagKey: String, 
  subjectKey: String, 
  subjectAttributes: [String: Any], 
  defaultValue: String
) -> Bool 
  ```

## Assignment logger 

To use the Eppo SDK for experiments that require analysis, pass in a callback logging function to the `init` function on SDK initialization. The SDK invokes the callback to capture assignment data whenever a variation is assigned. The assignment data is needed in the warehouse to perform analysis.

The code below illustrates an example implementation of a logging callback using [Segment](https://segment.com/), but you can use any system you'd like. Here we define an implementation of the Eppo `AssignmentLogger`:

```swift
// Example of a simple assignmentLogger function
func segmentAssignmentLogger(assignment: Assignment) {
    let assignmentDictionary: [String: Any] = [
        "allocation": assignment.allocation,
        "experiment": assignment.experiment,
        "featureFlag": assignment.featureFlag,
        "variation": assignment.variation,
        "subject": assignment.subject,
        "timestamp": assignment.timestamp
    ]

    analytics.track(
        name: "Eppo Assignment", 
        properties: TrackProperties(assignmentDictionary)
    )
}

eppoClient = try await EppoClient.initialize(sdkKey: "mock-sdk-key", assignmentLogger: segmentAssignmentLogger)
```

## Publishing releases

Swift Package Manager relies on semantic versioning without a prefix, such as `v`.

When publishing a release of the Swift SDK, use a git tag such as `3.2.1`.

## Philosophy

Eppo's SDKs are built for simplicity, speed and reliability. Flag configurations are compressed and distributed over a global CDN (Fastly), typically reaching your servers in under 15ms. Server SDKs continue polling Eppo’s API at 30-second intervals. Configurations are then cached locally, ensuring that each assignment is made instantly. Evaluation logic within each SDK consists of a few lines of simple numeric and string comparisons. The typed functions listed above are all developers need to understand, abstracting away the complexity of the Eppo's underlying (and expanding) feature set.
