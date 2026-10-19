import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Unicode version").font(.headline).foregroundStyle(Palette.ink)
                    CatalogEditionPicker()
                    Text("The latest release is selected by default. Choose either of the two previous releases, or opt in to the development draft. Your choice applies to the app and keyboard.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    if let message = preferences.editionSaveError {
                        Text(message).font(.caption).foregroundStyle(Palette.accent)
                            .accessibilityIdentifier("unicodeEdition.saveError")
                    }
                }
                .padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))

                NavigationLink {
                    KeyboardKeySettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Customize keyboard keys").font(.headline)
                            Text("Tap mappings, long press and swipe choices.")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }.accessibilityIdentifier("keyboardKeySettings")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard layout").font(.headline).foregroundStyle(Palette.ink)
                    Toggle("Show symbol bar", isOn: Binding(get: { preferences.showsSymbolBar }, set: { preferences.selectSymbolBar($0) }))
                        .accessibilityIdentifier("showsSymbolBar")
                    if preferences.showsSymbolBar {
                        Toggle("Show search bar instead", isOn: Binding(get: { preferences.searchBarInsteadOfSymbols }, set: { preferences.selectSearchBarInsteadOfSymbols($0) }))
                            .accessibilityIdentifier("searchBarInsteadOfSymbols")
                    }
                    Text("A fixed layout with a number row and larger keys. The optional top row shows symbols or Unicode search.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))

                if UIDevice.current.userInterfaceIdiom == .pad {
                VStack(alignment: .leading, spacing: 12) {
                    Text("iPad keyboard").font(.headline).foregroundStyle(Palette.ink)
                    Picker("Landscape layout", selection: Binding(get: { preferences.padLayout }, set: { preferences.selectPadLayout($0) })) {
                        ForEach(KeyboardPadLayout.allCases, id: \.rawValue) { Text($0.title).tag($0).accessibilityIdentifier("padLayout.option.\($0.rawValue)") }
                    }.pickerStyle(.menu).accessibilityIdentifier("padLayout").accessibilityValue(preferences.padLayout.rawValue)
                    Text("The number row is always present. On a wide landscape iPad, choose iPad styling, compact ANSI punctuation, or a full ANSI number row. In both orientations, symbol switching and Hide Keyboard sit to the right of Space.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Picker("Swipe-down symbols", selection: Binding(get: { preferences.padSymbolMapping }, set: { preferences.selectPadSymbolMapping($0) })) {
                        ForEach(KeyboardPadSymbolMapping.allCases, id: \.rawValue) { Text($0.title).tag($0).accessibilityIdentifier("padSymbolMapping.option.\($0.rawValue)") }
                    }.pickerStyle(.menu).accessibilityIdentifier("padSymbolMapping").accessibilityValue(preferences.padSymbolMapping.rawValue)
                    Text("Choose standard, iPad or macOS U.S. Option symbols. macOS mapping offers Option first and Shift–Option next; a visible digit row keeps its complementary Q–P symbols. Hold shows accents, Up shows opposite-case letters, and Down offers unused Option symbols. Customize individual gestures above. Reopen the keyboard to apply; Full Access is not required.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }

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
                    Label("Favorites & touch feedback", systemImage: "hand.tap").font(.headline)
                    Text("Saved and the keyboard’s Favorites board share your explicit favorites on this device. Allow Full Access in iOS keyboard settings to sync saves and removals from the keyboard back to the app. With it off, app favorites reach the keyboard, while keyboard changes wait locally. Custom boards and Recently used stay separate.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("Keys highlight while touched. Light haptics are available on supported iPhones with Full Access. No typing, searches or favorites are sent to a server, even with Full Access enabled.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Extra Unicode fonts", isOn: Binding(get: { preferences.useUnicodeFonts }, set: { preferences.selectUnicodeFonts($0) }))
                        .font(.headline).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("extraUnicodeFonts")
                    Text("Off by default. Use bundled fonts for some missing character previews. Emoji and interface text keep iOS fonts; other apps use their own fonts. New draft coverage is limited.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("This setting applies to both the app and keyboard. It does not require Full Access.")
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

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show keyboard collapse key", isOn: Binding(get: { preferences.showsCollapseKey }, set: { preferences.selectCollapseKey($0) }))
                        .font(.headline).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("showKeyboardCollapseKey")
                    Text("Off by default on phones and narrow iPad layouts. Wide iPad always includes Hide Keyboard to the right of Space.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))

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
                    Text("UNICODE \(preferences.catalog.version)")
                        .font(.caption.monospaced().weight(.semibold)).foregroundStyle(Palette.accent)
                    Text("All four versions are bundled offline. Draft assignments may change, and iOS fonts may not display every new character. Hold or hover over any character for its name, description and properties.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    NavigationLink("Unicode data & license") { UnicodeLicenseView() }.font(.caption)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
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
                    .keyboardType(.default)
                    .textInputAutocapitalization(.sentences)
                    .font(compact ? .body : .title2)
                    .padding(compact ? 4 : 12).scrollContentBackground(.hidden)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("keyboardTestInput")
                if !compact {
                    Text("Type English normally, or tap Unicode to search and browse every character.")
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
