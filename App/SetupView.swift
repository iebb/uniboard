import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: "keyboard").font(.system(size: 39, weight: .light)).foregroundStyle(Palette.accent)
                    Text("A keyboard with\na little more to say.")
                        .font(.system(size: 35, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Bring every character to the apps you use.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }.padding(.top, 8)

                VStack(spacing: 0) {
                    step(1, title: "Open keyboard settings", detail: "Settings → General → Keyboard → Keyboards.")
                    Divider().padding(.leading, 65)
                    step(2, title: "Add Uniboard", detail: "Choose Add New Keyboard…, then Uniboard.")
                    Divider().padding(.leading, 65)
                    step(3, title: "Make the switch", detail: "In any text field, hold the globe key and choose Uniboard.")
                }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.right")
                        .font(.headline).frame(maxWidth: .infinity).padding(17)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))

                NavigationLink {
                    KeyboardTestView()
                } label: {
                    HStack {
                        Label("Try your keyboard", systemImage: "text.cursor")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline.weight(.semibold)).padding(18)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 17))
                }.accessibilityIdentifier("tryKeyboard")

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Extra Unicode fonts", isOn: $preferences.useUnicodeFonts)
                        .font(.headline).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("extraUnicodeFonts")
                    Text("Off by default. Use bundled fonts for some missing character previews. Emoji and interface text keep iOS fonts; other apps use their own fonts. New draft coverage is limited.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("The app and keyboard remember this setting separately. Use the Fonts menu in the keyboard to change its previews.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    NavigationLink {
                        FontLicenseView()
                    } label: {
                        Label("Font licenses", systemImage: "doc.text")
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("fontLicenses")
                }
                .padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Private, by design", systemImage: "lock.shield")
                        .font(.headline).foregroundStyle(Palette.ink)
                    Text("Uniboard searches its bundled Unicode database. No internet, accounts, or Full Access required. Uniboard does not send your searches or typing to a server.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Text("iOS uses its own keyboard in password and phone-number fields. Some apps also disable third-party keyboards.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    HStack(spacing: 20) {
                        Link("Privacy policy", destination: URL(string: "https://docs.kitta.co/uniboard/")!)
                        Link("Help & support", destination: URL(string: "https://uniboard-dxm.pages.dev/support/")!)
                    }.font(.subheadline)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    CatalogControls(showSort: false)
                    Text("UNICODE \(preferences.catalog.version)")
                        .font(.caption.monospaced().weight(.semibold)).foregroundStyle(Palette.accent)
                    Text("Switch between the latest Unicode release and the development draft, both bundled offline. The app and keyboard remember their own choices. Draft assignments may change, and your iOS fonts may not display every new character. Hold or hover over any character for its name, description and properties.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    NavigationLink("Unicode data & license") { UnicodeLicenseView() }.font(.caption)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Set up Uniboard").navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(String(number)).font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(Palette.accent).frame(width: 31, height: 31)
                .background(Palette.soft, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
}

struct KeyboardTestView: View {
    @State private var text = ""
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 220
            VStack(alignment: .leading, spacing: compact ? 8 : 18) {
                if !compact {
                    Text("Tap below, then hold 🌐 to choose Uniboard.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                TextEditor(text: $text)
                    .font(compact ? .body : .title2)
                    .padding(compact ? 4 : 12).scrollContentBackground(.hidden)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("keyboardTestInput")
                if !compact {
                    Text("Search by name, description, block, or code point. Tap any character to insert it at the cursor.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, compact ? 4 : 22)
        }.background(Palette.background)
            .navigationTitle("Try Uniboard").navigationBarTitleDisplayMode(.inline)
    }
}

struct UnicodeLicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "Unicode-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Unicode data © Unicode, Inc. Distributed under the Unicode License v3. See unicode.org/license.txt."
        }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Unicode data").font(.title2.weight(.semibold))
                Text("Names, aliases, descriptions, and blocks come from the Unicode Character Database, including the latest draft data.")
                Link("Official Unicode development data", destination: URL(string: "https://github.com/unicode-org/unicodetools")!)
                Text(license).font(.caption).textSelection(.enabled)
            }.padding(24).foregroundStyle(Palette.ink)
        }.background(Palette.background).navigationTitle("Data & license").navigationBarTitleDisplayMode(.inline)
    }
}

struct FontLicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Bundled preview fonts").font(.title2.weight(.semibold))
                Text("Extra Unicode fonts are optional and off by default. They are used only for character previews in Uniboard. Coverage is incomplete, especially for new draft characters; inserted text keeps the receiving app’s fonts.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Text(UnicodeFontSupport.licenseText)
                    .font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("fontLicenseText")
            }
            .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .foregroundStyle(Palette.ink)
        }
        .background(Palette.background)
        .navigationTitle("Font licenses").navigationBarTitleDisplayMode(.inline)
    }
}
