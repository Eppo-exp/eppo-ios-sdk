protocol EppoHttpClient {
    func get() throws;
    func post() throws;
}

class NetworkEppoHttpClient : EppoHttpClient {
    public init() {}

    func get() throws {}
    func post() throws {}
}
