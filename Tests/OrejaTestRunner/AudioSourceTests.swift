import Foundation
import OrejaAudio
import OrejaCore

@MainActor
func runAudioSourceSuite(_ t: Harness) {
    print("\nAudio sources")

    t.run("the catalog never lists a music player or Oreja itself as an AI source") {
        for bundle in AISourceCatalog.musicPlayerBundleIdentifiers {
            t.expect(!AISourceCatalog.isSelectable(bundleIdentifier: bundle), "\(bundle) must not be selectable")
        }
        t.expect(!AISourceCatalog.isSelectable(bundleIdentifier: "app.oreja.van-gogh"))
        t.expect(!AISourceCatalog.isSelectable(bundleIdentifier: nil))
        t.expect(AISourceCatalog.isSelectable(bundleIdentifier: "com.apple.Music.helper") == false, "music helpers are excluded too")
        t.expect(AISourceCatalog.isSelectable(bundleIdentifier: "com.anthropic.claudefordesktop"))
    }

    t.run("Safari remains a listen source but is excluded from safe target muting") {
        t.expect(AISourceCatalog.isSelectable(bundleIdentifier: "com.apple.Safari"))
        t.expect(!AISourceCatalog.supportsTargetMute(bundleIdentifier: "com.apple.Safari"))
        t.expect(AISourceCatalog.supportsTargetMute(bundleIdentifier: "com.google.Chrome"))
        t.expect(AISourceCatalog.targetMuteBundleIDRoots(for: .safari) == nil)
        t.expectEqual(AISourceCatalog.targetMuteBundleIDRoots(for: .egoLite), ["com.citrolabs.ego"])
        t.expectEqual(AISourceCatalog.targetMuteBundleIDRoots(for: .chrome), ["com.google.Chrome"])
        t.expectEqual(AISourceCatalog.targetMuteBundleIDRoots(for: .chatGPTDesktop), AISourceCatalog.chatGPTBundleIdentifiers)
        t.expect(AudioProcessCatalog.matches(bundleID: "com.google.Chrome.helper", roots: ["com.google.Chrome"]))
        t.expect(!AudioProcessCatalog.matches(bundleID: "com.google.ChromeBeta", roots: ["com.google.Chrome"]))
    }

    t.run("normalizing drops music players and duplicates, keeping the first") {
        let music = AISourceSelection.app(bundleIdentifier: "com.apple.Music", displayName: "Music")
        let claude = AISourceSelection.app(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude")
        let claudeAgain = AISourceSelection.app(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude copy")
        let result = AISourceCatalog.normalized([music, claude, .chatGPTDesktop, claudeAgain])
        t.expectEqual(result.map(\.bundleIdentifier), ["com.anthropic.claudefordesktop", "com.openai.codex"])
        t.expectEqual(result.first?.displayName, "Claude")
    }

    t.run("several selected apps share one tap with merged prefixes") {
        let descriptor = AIAudioSourceDescriptor(selections: [
            .chatGPTDesktop,
            .app(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude"),
            .chrome,
        ])
        t.expect(descriptor.bundleIdentifierPrefixes.contains("com.openai."))
        t.expect(descriptor.bundleIdentifierPrefixes.contains("com.anthropic.claudefordesktop"))
        t.expect(descriptor.bundleIdentifierPrefixes.contains("com.google.Chrome"))
        t.expectEqual(
            descriptor.bundleIdentifierPrefixes.count,
            Set(descriptor.bundleIdentifierPrefixes).count,
            "no prefix appears twice"
        )
        t.expectEqual(descriptor.displayName, "ChatGPT, Claude, Google Chrome")
        t.expect(descriptor.isExperimental, "a browser in the set makes the set experimental")
    }

    t.run("a set with only desktop apps is not experimental") {
        let descriptor = AIAudioSourceDescriptor(selections: [
            .chatGPTDesktop,
            .app(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code"),
        ])
        t.expect(!descriptor.isExperimental)
    }

    t.run("an empty selection listens to nothing") {
        let descriptor = AIAudioSourceDescriptor(selections: [])
        t.expect(descriptor.bundleIdentifierPrefixes.isEmpty)
        t.expectEqual(descriptor.displayName, "no audio app")
    }

    t.run("known coding agents and terminals are matched and categorised") {
        let vscode = AISourceCatalog.profile(for: "com.microsoft.VSCode")
        t.expectEqual(vscode?.category, .codingAgent)
        t.expectEqual(AISourceSelection.app(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal").category, .codingAgent)
        t.expectEqual(AISourceSelection.chatGPTDesktop.category, .aiAssistant)
        t.expectEqual(AISourceSelection.chrome.category, .browser)
        t.expectEqual(AISourceSelection.app(bundleIdentifier: "com.unknown.thing", displayName: "Thing").category, .other)
    }

    t.run("the ChatGPT helper still resolves to the ChatGPT profile") {
        t.expect(AISourceCatalog.isChatGPT(bundleIdentifier: "com.openai.codex.helper"))
        t.expectEqual(AISourceCatalog.profile(for: "com.openai.codex.helper")?.category, .aiAssistant)
    }

    t.run("the selection for a known app keeps its legacy kind") {
        let chatGPT = KnownAudioApp(bundleIdentifier: "com.openai.codex", displayName: "ChatGPT", category: .aiAssistant)
        t.expectEqual(AISourceCatalog.selection(for: chatGPT).kind, .chatGPTDesktop)
        let chrome = AISourceCatalog.knownApps.first { $0.bundleIdentifier == "com.google.Chrome" }!
        t.expectEqual(AISourceCatalog.selection(for: chrome).kind, .browser)
        let vscode = AISourceCatalog.knownApps.first { $0.bundleIdentifier == "com.microsoft.VSCode" }!
        t.expectEqual(AISourceCatalog.selection(for: vscode).kind, .app)
    }

    t.run("every known app has a unique bundle identifier and a non-empty name") {
        let ids = AISourceCatalog.knownApps.map(\.bundleIdentifier)
        t.expectEqual(ids.count, Set(ids).count, "duplicate bundle identifiers in the catalog")
        t.expect(AISourceCatalog.knownApps.allSatisfy { !$0.displayName.isEmpty && !$0.prefixes.isEmpty })
        t.expect(AISourceCatalog.knownApps.allSatisfy { app in AISourceCatalog.isSelectable(bundleIdentifier: app.bundleIdentifier) })
    }

    t.run("settings written with the single-source key still load") {
        let legacy = #"{"aiSource": {"kind": "browser", "bundleIdentifier": "com.google.Chrome", "displayName": "Google Chrome"}}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: legacy.data(using: .utf8)!)
        t.expectEqual(decoded.aiSources.map(\.bundleIdentifier), ["com.google.Chrome"])
        t.expectEqual(decoded.aiSources.first?.kind, .browser)
    }

    t.run("settings written with the multi-source key keep every app in order") {
        let json = #"{"aiSources": [{"kind": "app", "bundleIdentifier": "com.microsoft.VSCode", "displayName": "Visual Studio Code"}, {"kind": "chatGPTDesktop", "bundleIdentifier": "com.openai.codex", "displayName": "ChatGPT"}]}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.expectEqual(decoded.aiSources.map(\.bundleIdentifier), ["com.microsoft.VSCode", "com.openai.codex"])
    }

    t.run("settings drop a music player stored as an AI source") {
        let json = #"{"aiSources": [{"kind": "app", "bundleIdentifier": "com.spotify.client", "displayName": "Spotify"}]}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.expect(decoded.aiSources.isEmpty, "a music player must not be an AI source")
    }

    t.run("an explicit empty selection is kept, not replaced by ChatGPT") {
        let json = #"{"aiSources": []}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.expect(decoded.aiSources.isEmpty)
    }

    t.run("a setting write keeps every other field intact") {
        let suiteName = "com.oreja.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "k")
        var settings = AppSettings(aiSources: [.chatGPTDesktop, .app(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude")])
        settings.onboardingCompleted = true
        store.save(settings)
        let loaded = store.load()
        t.expectEqual(loaded.aiSources, settings.aiSources)
        t.expectEqual(loaded.onboardingCompleted, true, "onboarding flag must survive a source change")
    }
}
