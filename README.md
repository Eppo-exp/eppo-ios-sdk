# Eppo iOS (Swift) SDK

[![Test and lint SDK](https://github.com/Eppo-exp/eppo-ios-sdk/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/Eppo-exp/eppo-ios-sdk/actions/workflows/unit-tests.yml)

[Eppo](https://www.geteppo.com/) is a modular flagging and experimentation analysis tool. Eppo's iOS SDK is built to make assignments for single user client applications. Before proceeding you'll need an Eppo account.

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
    try await EppoClient.initialize(apiKey: "SDK-KEY-FROM-DASHBOARD");
}
```

#### Assign anywhere

Assignment is a synchronous operation.

```swift
let assignment = try eppoClient.getStringAssignment(
    "new-user-onboarding",
    user.id,
    user.attributes,
    "control"
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
                "new-user-onboarding",
                user.id,
                user.attributes,
                "control"
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
                try await EppoClient.initialize(apiKey: "SDK-KEY-FROM-DASHBOARD");
                self.assignment = try EppoClient.shared().getStringAssignment(
                    "new-user-onboarding",
                    user.id,
                    user.attributes,
                    "control"
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
getJSONAssignment(...)
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

eppoClient = EppoClient("mock-sdk-key", assignmentLogger: segmentAssignmentLogger)
```

## Philosophy

Eppo's SDKs are built for simplicity, speed and reliability. Flag configurations are compressed and distributed over a global CDN (Fastly), typically reaching your servers in under 15ms. Server SDKs continue polling Eppo’s API at 30-second intervals. Configurations are then cached locally, ensuring that each assignment is made instantly. Evaluation logic within each SDK consists of a few lines of simple numeric and string comparisons. The typed functions listed above are all developers need to understand, abstracting away the complexity of the Eppo's underlying (and expanding) feature set.
