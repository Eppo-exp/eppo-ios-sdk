import XCTest

@testable import eppo_flagging

class EppoMockHttpClient: EppoHttpClient {
    public init() {}

    public func get() throws {}
    public func post() throws {}
}

final class eppoClientTests: XCTestCase {
    private var eppoHttpClient: EppoHttpClient = EppoMockHttpClient();
    private var eppoClient: EppoClient?;
    
    override func setUp() {
        super.setUp();

        try? eppoClient = EppoClient(
            "mock-api-key",
            "http://localhost:4001",
            nil,
            nil
        );
    }
}
