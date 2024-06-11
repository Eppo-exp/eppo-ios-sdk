import Foundation

import Foundation
import CryptoKit

// Lookup table for md5 hashes to the ONE_OF enum
let md5ToOperator: [String: UFC_RuleConditionOperator] = [
    Utils.getMD5Hex(UFC_RuleConditionOperator.lessThan.rawValue): .lessThan,
    Utils.getMD5Hex(UFC_RuleConditionOperator.lessThanEqual.rawValue): .lessThanEqual,
    Utils.getMD5Hex(UFC_RuleConditionOperator.greaterThan.rawValue): .greaterThan,
    Utils.getMD5Hex(UFC_RuleConditionOperator.greaterThanEqual.rawValue): .greaterThanEqual,
    Utils.getMD5Hex(UFC_RuleConditionOperator.matches.rawValue): .matches,
    Utils.getMD5Hex(UFC_RuleConditionOperator.notMatches.rawValue): .notMatches,
    Utils.getMD5Hex(UFC_RuleConditionOperator.oneOf.rawValue): .oneOf,
    Utils.getMD5Hex(UFC_RuleConditionOperator.notOneOf.rawValue): .notOneOf,
    Utils.getMD5Hex(UFC_RuleConditionOperator.isNull.rawValue): .isNull,
]

let md5ToVariationType: [String: UFC_VariationType] = [
    Utils.getMD5Hex(UFC_VariationType.string.rawValue): .string,
    Utils.getMD5Hex(UFC_VariationType.numeric.rawValue): .numeric,
    Utils.getMD5Hex(UFC_VariationType.boolean.rawValue): .boolean,
    Utils.getMD5Hex(UFC_VariationType.json.rawValue): .json,
]

