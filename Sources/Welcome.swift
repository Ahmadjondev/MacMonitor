import SwiftUI
import AppKit

// First-launch onboarding: intro, language, key permissions, then "Get Started".
struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loc = Loc.shared
    let onDone: () -> Void

    private var appIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 76, height: 76)
            }
            Text("Mac Monitor").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            Text(loc.t("welcome_sub"))
                .font(.system(size: 12.5)).foregroundColor(Pal.sub)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                feature("memorychip", loc.t("memory"))
                feature("cpu", loc.t("processor"))
                feature("globe", loc.t("network"))
                feature("internaldrive", loc.t("storage"))
            }
            .padding(.vertical, 4)

            Divider().overlay(Pal.cardBorder)

            row(loc.t("language")) {
                Picker("", selection: $loc.lang) {
                    ForEach(Loc.langs, id: \.self) { Text(Loc.langName[$0] ?? $0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            Toggle(isOn: $settings.notify) {
                Text(loc.t("notifications")).font(.system(size: 12.5)).foregroundColor(.white)
            }
            .toggleStyle(.switch).tint(Pal.blue)
            Toggle(isOn: $settings.launchAtLogin) {
                Text(loc.t("launch_login")).font(.system(size: 12.5)).foregroundColor(.white)
            }
            .toggleStyle(.switch).tint(Pal.blue)

            Button(action: onDone) {
                Text(loc.t("get_started"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(LinearGradient(colors: [Pal.purple, Pal.blue], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 380)
        .background(Pal.bg)
    }

    func feature(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 17)).foregroundColor(Pal.blue)
            Text(label).font(.system(size: 10)).foregroundColor(Pal.sub).lineLimit(1)
        }
        .frame(width: 64)
    }

    @ViewBuilder
    func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundColor(.white)
            Spacer()
            control()
        }
    }
}
