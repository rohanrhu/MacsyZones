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

struct GitHubRelease {
    let version: String
    let releaseURL: URL
}

class AppUpdater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdatable: Bool?
    
    @Published var latestVersion: String?
    @Published var latestReleaseURL: URL?
    
    let updater = GitHubUpdater()
    
    func checkForUpdates() {
        Task { @MainActor in
            self.isChecking = true
        }
        
        updater.checkForUpdates { release in
            Task { @MainActor in
                self.isChecking = false

                guard let release else {
                    self.latestVersion = nil
                    self.latestReleaseURL = nil
                    self.isUpdatable = false
                    return
                }
                
                self.latestVersion = release.version
                self.latestReleaseURL = release.releaseURL
                self.isUpdatable = true
            }
        }
    }
}

func isVersionGreater(_ version: String, than otherVersion: String) -> Bool {
    let cleanVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let cleanOtherVersion = otherVersion.hasPrefix("v") ? String(otherVersion.dropFirst()) : otherVersion
    
    let versionComponents = cleanVersion.split(separator: ".")
    let otherVersionComponents = cleanOtherVersion.split(separator: ".")
    
    let minComponents = min(versionComponents.count, otherVersionComponents.count)
    
    for i in 0..<minComponents {
        guard let vNum = Int(versionComponents[i]), let otherNum = Int(otherVersionComponents[i]) else {
            if versionComponents[i] > otherVersionComponents[i] {
                return true
            } else if versionComponents[i] < otherVersionComponents[i] {
                return false
            }
            continue
        }
        
        if vNum > otherNum {
            return true
        } else if vNum < otherNum {
            return false
        }
    }
    
    return versionComponents.count > otherVersionComponents.count
}

class GitHubAPI {
    let session = URLSession.shared

    func checkLatestRelease(onChecked: @escaping (GitHubRelease?) -> Void) {
        let urlString = "https://api.github.com/repos/rohanrhu/MacsyZones/releases/latest"
        guard let url = URL(string: urlString) else {
            onChecked(nil)
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                onChecked(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let releaseURLString = json["html_url"] as? String
                {
                    let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                    let isGreater = isVersionGreater(version, than: appVersion)

                    guard isGreater, let releaseURL = URL(string: releaseURLString) else {
                        onChecked(nil)
                        return
                    }

                    onChecked(GitHubRelease(version: version, releaseURL: releaseURL))
                } else {
                    onChecked(nil)
                }
            } catch {
                debugLog("Error parsing JSON:")
                dump(error)
                onChecked(nil)
            }
        }
        
        task.resume()
    }
}

class GitHubUpdater {
    let githubAPI = GitHubAPI()
    
    func checkForUpdates(onChecked: ((GitHubRelease?) -> Void)? = nil) {
        githubAPI.checkLatestRelease { latestRelease in
            onChecked?(latestRelease)
        }
    }
}
