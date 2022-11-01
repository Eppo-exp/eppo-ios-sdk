import Foundation

struct flagConfigJSON : Decodable {
    var flags: [String : FlagConfig];
}

func requestFlagConfiguration(_ flagKey: String, _ httpClient: EppoHttpClient) throws -> [String : FlagConfig] {
    guard let url = URL(string: "/api/randomized_assignment/v2/config") else {
        throw EppoHttpClientErrors.invalidURL;
    }

    let (urlData, _) = try httpClient.get(url);
    let rval = try JSONDecoder().decode(flagConfigJSON.self, from: urlData);
    
    return rval.flags;
}
