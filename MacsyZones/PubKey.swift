//
// MacsyZones, macOS system utility for managing windows on your Mac.
// 
// https://macsyzones.com
// 
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
// 
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import Foundation
import Security

class PublicKeyProvider {
    static let publicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA8jqZV66kWFEZv1y2J4d4NFRyasN3sS4digM4Lo1uh3ZEogPjvxHQEUYT9tlHt9lQJl7aSOsHnB3efxxzKzykFlWoTxyPofVPf2wC5kVac7R/ZhtnhK5asuX2unTQvZi+EHbQisqY2dy1U4rwWKs2US7/QbZawO97v3f17lvbcn0covXYSdOGN+KyC2bskGdYrTPZyVIcHh47mOuj5VpFUBppbv48YQVLsymEdeVGXUlkHUCtWMqMxx33NzJPLPt0+/vdjcJzNiBLhHsCLqRuXiLr9YWc/D2zDuygDb9j7nxROCuXaaDLVECmKdbNq++lQ/KYmmqI7bETh7alWFg9eQIDAQAB"
    static let xorKey = "MIAU"
    
    static var PublicKey: SecKey { getPublicKey() }
    
    static func getPublicKey() -> SecKey {
            let publicKeyData = Data(base64Encoded: publicKey)!

            let keyDict: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits as String: 2048
            ]

            return SecKeyCreateWithData(publicKeyData as CFData, keyDict as CFDictionary, nil)!
        }
}
