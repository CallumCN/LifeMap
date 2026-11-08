import SwiftUI

/// Lets the user narrow trips by how much of a song was heard and by music source.
struct TripFilterSheet: View {
    @Binding var filter: TripFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Song, artist, or album", text: $filter.songQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Song")
                }

                Section {
                    LabeledContent("At least", value: Formatters.percent(filter.minFraction))
                    Slider(value: $filter.minFraction, in: 0...1, step: 0.05) {
                        Text("Minimum fraction listened")
                    }
                    .onChange(of: filter.minFraction) { _, newValue in
                        if newValue > filter.maxFraction { filter.maxFraction = newValue }
                    }

                    LabeledContent("At most", value: Formatters.percent(filter.maxFraction))
                    Slider(value: $filter.maxFraction, in: 0...1, step: 0.05) {
                        Text("Maximum fraction listened")
                    }
                    .onChange(of: filter.maxFraction) { _, newValue in
                        if newValue < filter.minFraction { filter.minFraction = newValue }
                    }
                } header: {
                    Text("Fraction of song listened")
                } footer: {
                    Text("Show trips containing a song that was listened to for between \(Formatters.percent(filter.minFraction)) and \(Formatters.percent(filter.maxFraction)) of its length. Use a high minimum to find songs you heard all the way through, or a low maximum to find songs you skipped.")
                }

                Section("Sources") {
                    ForEach(MusicSource.allCases) { source in
                        Toggle(isOn: binding(for: source)) {
                            Label(source.displayName, systemImage: source.symbolName)
                        }
                        .tint(source.tint)
                    }
                }

                Section {
                    Button("Reset filters", role: .destructive) {
                        filter = TripFilter()
                    }
                    .disabled(filter.isDefault)
                }
            }
            .navigationTitle("Filter trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for source: MusicSource) -> Binding<Bool> {
        Binding(
            get: { filter.sources.contains(source) },
            set: { isOn in
                if isOn {
                    filter.sources.insert(source)
                } else {
                    filter.sources.remove(source)
                }
            }
        )
    }
}
