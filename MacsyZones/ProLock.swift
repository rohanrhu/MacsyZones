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

class VerifyResult {
    var isValid: Bool = false
    var owner: String? = nil
    
    init(isValid: Bool = false, owner: String? = nil) {
        self.isValid = isValid
        self.owner = owner
    }
}

class ProLock: ObservableObject {
    @Published var isPro: Bool = false
    @Published var owner: String?
    
    private var licenseKey: String = ""
    private let licenseFileName = "LicenseKey.txt"
    
    init() {
        load()
    }
    
    func load() {
        let fileManager = FileManager.default
        let appName = Bundle.main.bundleIdentifier ?? "MacsyZones"
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportDirectory.appendingPathComponent(appName)
        let filePath = appDirectory.appendingPathComponent(licenseFileName)
        
        if fileManager.fileExists(atPath: filePath.path) {
            do {
                licenseKey = try String(contentsOf: filePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                let verifyResult = validateLicenseKey(licenseKey)
                if verifyResult.isValid {
                    isPro = true
                    owner = verifyResult.owner
                } else {
                    isPro = false
                }
            } catch {
                debugLog("Error loading license key: \(error)")
            }
        } else {
            debugLog("LicenseKey.txt file does not exist")
        }
    }
    
    func save() {
        let fileManager = FileManager.default
        let appName = Bundle.main.bundleIdentifier ?? "MacsyZones"
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportDirectory.appendingPathComponent(appName)
        
        if !fileManager.fileExists(atPath: appDirectory.path) {
            do {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugLog("Error creating app directory: \(error)")
                return
            }
        }
        
        let filePath = appDirectory.appendingPathComponent(licenseFileName)
        
        do {
            try licenseKey.write(to: filePath, atomically: true, encoding: .utf8)
            debugLog("License key saved")
        } catch {
            debugLog("Error saving license key: \(error)")
        }
    }
    
    func setLicenseKey(_ key: String) -> Bool {
        let verifyResult = validateLicenseKey(key)
        
        isPro = verifyResult.isValid
        owner = verifyResult.owner
        
        if isPro {
            licenseKey = key
            save()
            return true
        } else {
            isPro = false
            return false
        }
    }
    
    private func validateLicenseKey(_ key: String) -> VerifyResult {
        return verifyMergedLicenseKey(publicKey: PublicKeyProvider.PublicKey, mergedLicenseKey: key)
    }
    
    func verifyMergedLicenseKey(publicKey: SecKey, mergedLicenseKey: String) -> VerifyResult {
        guard let decodedMergedKeyData = Data(base64Encoded: mergedLicenseKey) else {
            return VerifyResult()
        }
        
        guard let decodedMergedKey = String(data: decodedMergedKeyData, encoding: .utf8) else {
            return VerifyResult()
        }
        
        let components = decodedMergedKey.split(separator: "|")
        guard components.count == 2 else {
            return VerifyResult()
        }
        
        let owner = components[0]
        let signatureBase64 = components[1]
        
        guard let signatureData = Data(base64Encoded: String(signatureBase64)) else {
            return VerifyResult()
        }
        
        guard let ownerData = owner.data(using: .utf8) else {
            return VerifyResult()
        }
        
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePSSSHA256,
            ownerData as CFData,
            signatureData as CFData,
            &error
        )

        if error != nil || !isValid {
            return VerifyResult()
        }

        return VerifyResult(isValid: true, owner: String(owner))
    }
}
