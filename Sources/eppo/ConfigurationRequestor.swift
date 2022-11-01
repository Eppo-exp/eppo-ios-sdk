import Foundation

struct flagConfigJSON : Decodable {
    var flags: [String : FlagConfig];
}

enum FlagRequestErrors : Error {
    case flagNotDefined;
}

func requestFlagConfiguration(_ flagKey: String, _ httpClient: EppoHttpClient) throws -> FlagConfig {
    guard let url = URL(string: "/api/randomized_assignment/v2/config") else {
        throw EppoHttpClientErrors.invalidURL;
    }

    let (urlData, _) = try httpClient.get(url);
    let flagConfigs = try JSONDecoder().decode(flagConfigJSON.self, from: urlData);
    guard let rval = flagConfigs.flags[flagKey] else {
        throw FlagRequestErrors.flagNotDefined;
    }
    
    return rval;
}
