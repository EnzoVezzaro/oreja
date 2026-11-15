import Foundation
import OrejaCore

/// Public Apple Events scripting dialects supported by the browser media adapter.
public enum BrowserMediaScriptDialect: Sendable, Equatable {
    case chromium
    case safari
}

/// Browser identity mapping and safe AppleScript source generation, kept separate so adapter
/// coverage and argument escaping can be tested without launching a browser.
public enum BrowserMediaScripting {
    public static let dialectsByBundleIdentifier: [String: BrowserMediaScriptDialect] = [
        "com.citrolabs.ego.lite": .chromium,
        "com.google.Chrome": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
        "company.thebrowser.Browser": .chromium,
        "com.apple.Safari": .safari,
    ]

    public static var supportedBundleIdentifiers: Set<String> {
        Set(dialectsByBundleIdentifier.keys)
    }

    public static func mediaControlJavaScript(mode: MusicInterruptionMode, duckPercent: Int) -> String {
        let modeName = mode == .duck ? "duck" : "pause"
        let level = Double(min(max(duckPercent, 1), 100)) / 100.0
        return """
        (() => {
          const key = '__orejaMediaControlV1';
          let s = window[key];
          if (!s) {
            s = { items: new Map(), mode: '\(modeName)', level: \(level), last: Date.now(), timer: 0 };
            document.querySelectorAll('audio,video').forEach(m => {
              if (m.paused || m.ended) return;
              const item = { volume: m.volume, appliedVolume: undefined, pausedByOreja: false, playbackOverride: false, volumeOverride: false, pauseCommandPending: false };
              s.items.set(m, item);
              item.onPause = e => {
                if (!e.isTrusted) return;
                if (item.pauseCommandPending) { item.pauseCommandPending = false; return; }
                item.playbackOverride = true;
              };
              item.onPlay = e => { if (e.isTrusted) item.playbackOverride = true; };
              m.addEventListener('pause', item.onPause, true);
              m.addEventListener('play', item.onPlay, true);
            });
            window[key] = s;
          }
          if (s.mode !== '\(modeName)') return 'mode-conflict';
          s.mode = '\(modeName)';
          s.level = \(level);
          s.last = Date.now();
          const restore = () => {
            s.items.forEach((item, m) => {
              m.removeEventListener('pause', item.onPause, true);
              m.removeEventListener('play', item.onPlay, true);
              if (!item.volumeOverride && item.appliedVolume !== undefined && Math.abs(m.volume - item.appliedVolume) < 0.001) m.volume = item.volume;
              if (item.pausedByOreja && !item.playbackOverride && m.paused) {
                const p = m.play(); if (p && p.catch) p.catch(() => {});
              }
            });
            s.items.clear();
            delete window[key];
          };
          const apply = () => {
            if (Date.now() - s.last > 1800) { restore(); clearInterval(s.timer); delete window[key]; return; }
            s.items.forEach((old, m) => {
              if (!m.isConnected) return;
              if (s.mode === 'duck') {
                if (old.volumeOverride) return;
                if (old.appliedVolume !== undefined && Math.abs(m.volume - old.appliedVolume) >= 0.001) { old.volumeOverride = true; return; }
                old.appliedVolume = Math.min(old.volume, s.level);
                m.volume = old.appliedVolume;
              }
              else if (old.playbackOverride) return;
              else if (old.pausedByOreja && !m.paused) old.playbackOverride = true;
              else if (!old.pausedByOreja && !m.paused) {
                old.pausedByOreja = true;
                old.pauseCommandPending = true;
                m.pause();
                setTimeout(() => { old.pauseCommandPending = false; }, 250);
              }
            });
          };
          apply();
          if (!s.timer) s.timer = setInterval(apply, 250);
          return 'ok';
        })()
        """
    }

    public static func controlScript(bundleIdentifier: String, javascript: String) -> String? {
        guard let dialect = dialectsByBundleIdentifier[bundleIdentifier] else { return nil }
        let argument = javascript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let command = dialect == .safari
            ? "do JavaScript \"\(argument)\" in t"
            : "execute t javascript \"\(argument)\""
        return """
        if application id "\(bundleIdentifier)" is running then
          tell application id "\(bundleIdentifier)"
            set failures to 0
            repeat with w in windows
              repeat with t in tabs of w
                try
                  set javascriptResult to \(command)
                on error
                  set failures to failures + 1
                end try
              end repeat
            end repeat
            return failures as text
          end tell
        end if
        """
    }
}
