import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @ObservedObject private var fontRules = FontRulePreferences.shared
    /// Explore's Private Use rows and planes, hidden by default.
    @AppStorage("exploreShowsPrivateUse") private var showsPrivateUse = false
    var body: some View {
        Form {
            Section {
                CatalogEditionPicker()
                if let message = preferences.editionSaveError {
                    Text(message).foregroundStyle(.red)
                        .accessibilityIdentifier("unicodeEdition.saveError")
                }
            } header: {
                Text("Unicode")
            } footer: {
                Text("The newest release is the default. You can also choose either of the two previous releases or the development draft. Applies to the app and keyboard.")
            }

            Section {
                NavigationLink { KeyboardLayoutsView() } label: {
                    LabeledContent("Layouts", value: preferences.alphabets.map(\.nativeName).joined(separator: ", "))
                }
                .accessibilityIdentifier("keyboardLayouts")
                NavigationLink("Customize Keys") { KeyboardKeySettingsView() }
                    .accessibilityIdentifier("keyboardKeySettings")
                NavigationLink { AutoCapitalizationSettingsView() } label: {
                    LabeledContent(AutoCapitalizationCopy.title, value: preferences.autoCapitalization.title)
                }
                .accessibilityIdentifier("keyboardAutoCapitalization")
                Toggle("Text Preview", isOn: Binding(get: { preferences.showsTextPreview }, set: { preferences.selectTextPreview($0) }))
                    .accessibilityIdentifier("showKeyboardTextPreview")
                Toggle("Hide Keyboard Key", isOn: Binding(get: { preferences.showsCollapseKey }, set: { preferences.selectCollapseKey($0) }))
                    .accessibilityIdentifier("showKeyboardCollapseKey")
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Hide Keyboard Key adds a key that closes the keyboard; wide iPad layouts always have one.")
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                Section {
                    Picker("Landscape Layout", selection: Binding(get: { preferences.padLayout }, set: { preferences.selectPadLayout($0) })) {
                        ForEach(KeyboardPadLayout.allCases, id: \.rawValue) { Text($0.title).tag($0).accessibilityIdentifier("padLayout.option.\($0.rawValue)") }
                    }.pickerStyle(.menu).accessibilityIdentifier("padLayout").accessibilityValue(preferences.padLayout.rawValue)
                } header: {
                    Text("iPad Keyboard")
                } footer: {
                    Text("On a wide landscape iPad, choose iPad styling, compact ANSI punctuation, or a full ANSI number row. Reopen the keyboard to apply; Full Access is not required.")
                }
            }

            Section {
                step(1, title: "Open Keyboard Settings", detail: "Settings → General → Keyboard → Keyboards")
                step(2, title: "Add Uniboard", detail: "Choose Add New Keyboard, then Uniboard.")
                step(3, title: "Switch Keyboards", detail: "In any text field, hold the globe key and choose Uniboard.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                NavigationLink("Try Your Keyboard") { KeyboardTestView() }
                    .accessibilityIdentifier("tryKeyboard")
            } header: {
                Text("Set Up Uniboard")
            } footer: {
                Text("The keyboard shows the pages you set up in Pages, including Favorites. Allow Full Access to sync favorites saved in the keyboard back to the app, and for light haptics on supported iPhones. Without it, pages and app favorites still reach the keyboard. Recently Used stays separate.")
            }

            Section {
                Toggle("Extra Unicode Fonts", isOn: Binding(get: { preferences.useUnicodeFonts }, set: { preferences.selectUnicodeFonts($0) }))
                    .accessibilityIdentifier("extraUnicodeFonts")
                Toggle("Private Use Area", isOn: $showsPrivateUse)
                    .accessibilityIdentifier("showPrivateUse")
                Toggle("ConScript (UCSUR)", isOn: Binding(get: { preferences.showsUCSUR }, set: { preferences.selectUCSUR($0) }))
                    .accessibilityIdentifier("showUCSUR")
                if preferences.showsUCSUR {
                    Toggle("Prefer ConScript over PUA", isOn: Binding(get: { preferences.prefersUCSUR }, set: { preferences.selectPrefersUCSUR($0) }))
                        .accessibilityIdentifier("preferUCSUR")
                }
                NavigationLink("Font Downloads") { FontPackDownloadsView() }
                    .accessibilityIdentifier("fontDownloads")
                NavigationLink { FontRulesView() } label: {
                    LabeledContent("Font Rules", value: FontRuleCopy.ruleCount(fontRules.rules.count))
                }
                .accessibilityIdentifier("fontRules")
                NavigationLink("Font Licenses") { FontLicenseView() }
                    .accessibilityIdentifier("fontLicenses")
            } header: {
                Text("Preview Fonts")
            } footer: {
                Text("Off by default. When iOS can’t draw a character or emoji, Uniboard previews it with a downloaded font instead. Characters iOS can’t draw itself are tinted red either way, since other apps use their own fonts. Applies to the app and keyboard without Full Access.")
            }

            Section {
                NavigationLink(ConfigurationCopy.title) { ConfigurationView() }
                    .accessibilityIdentifier("configuration")
            }

            Section {
                LabeledContent("Unicode Data", value: preferences.catalog.version)
                NavigationLink("Data & License") { UnicodeLicenseView() }
                Link("Privacy Policy", destination: URL(string: "https://docs.kitta.co/uniboard/")!)
                Link("Help & Support", destination: URL(string: "https://uniboard-dxm.pages.dev/support/")!)
            } header: {
                Text("About")
            } footer: {
                Text("Uniboard searches its bundled Unicode database offline, with no accounts. Your typing, searches and favorites are never sent to a server, even with Full Access. iOS uses its own keyboard in password and phone-number fields, and some apps disallow third-party keyboards.")
            }
        }
        .accessibilityIdentifier("settingsForm")
        .navigationTitle("Settings")
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "\(number).circle.fill").foregroundStyle(.tint)
        }
    }
}

/// Settings → Keyboard → Auto-Capitalization: the five modes, each saved
/// as soon as it's chosen. Affects new typing in the keyboard only.
struct AutoCapitalizationSettingsView: View {
    @EnvironmentObject private var preferences: CatalogPreferences

    var body: some View {
        List {
            Section {
                ForEach(AutoCapitalizationMode.allCases, id: \.self) { mode in
                    let selected = preferences.autoCapitalization == mode
                    Button {
                        preferences.selectAutoCapitalization(mode)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                // Explicit label colors: a List button would tint them.
                                Text(mode.title).foregroundStyle(Color(uiColor: .label))
                                Text(mode.summary).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if selected {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 56 - 16)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(mode.title)
                    .accessibilityValue(mode.summary)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("autoCapitalization.\(mode.rawValue)")
                }
            } header: {
                // No explicit .secondary: inside a header it fades a level, to about 1.85:1.
                Text(AutoCapitalizationCopy.header).font(.footnote).textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AutoCapitalizationCopy.footer)
                    Text(AutoCapitalizationCopy.footerDetail)
                    if let message = preferences.autoCapitalizationSaveError {
                        Text(message).foregroundStyle(.red).accessibilityIdentifier("autoCapitalization.saveError")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AutoCapitalizationCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("autoCapitalizationList")
    }
}

struct KeyboardTestView: View {
    @State private var text = ""
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    private var compactPhone: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geometry in
            let compact = compactPhone || geometry.size.height < 220
            VStack(alignment: .leading, spacing: compact ? 8 : 18) {
                if !compact {
                    Text("Tap below, then hold 🌐 to choose Uniboard.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    if compactPhone {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").frame(width: 36, height: 44)
                        }
                        .accessibilityLabel("Back to keyboard settings")
                        .accessibilityIdentifier("keyboardTestBack")
                    }
                    TextEditor(text: $text)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.sentences)
                        .font(compact ? .body : .title2)
                        .frame(height: compactPhone ? 44 : nil, alignment: .top)
                        .padding(compact ? 4 : 12).scrollContentBackground(.hidden)
                        .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("keyboardTestInput")
                }
                if !compact {
                    Text("Type English normally, or tap Unicode to search and browse every character.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, compact ? 8 : 22).padding(.vertical, compact ? 0 : 22)
        }.background { Color.groupedBackground.ignoresSafeArea() } // also behind the keyboard's corners
            .navigationTitle("Try Uniboard").navigationBarTitleDisplayMode(.inline)
            .toolbar(compactPhone ? .hidden : .visible, for: .navigationBar)
    }
}

struct UnicodeLicenseView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
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
                Text("Names, aliases, descriptions, and blocks come from the Unicode Character Database, including the latest draft data.")
                Link("Official Unicode development data", destination: URL(string: "https://github.com/unicode-org/unicodetools")!)
                if preferences.showsUCSUR {
                    Link("ConScript data © Kreative Software", destination: URL(string: "https://www.kreativekorp.com/ucsur/")!)
                }
                Text(license).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle("Data & License").navigationBarTitleDisplayMode(.inline)
    }
}

struct FontLicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Extra Unicode fonts are optional and off by default. They are used only for character previews in Uniboard. Coverage is incomplete, especially for new draft characters; inserted text keeps the receiving app’s fonts.")
                Text(UnicodeFontSupport.licenseText)
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityIdentifier("fontLicenseText")
            }
            .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Font Licenses").navigationBarTitleDisplayMode(.inline)
    }
}
