import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: MeasureViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.historyStore.records.isEmpty {
                    ContentUnavailableView(
                        "暂无测量历史",
                        systemImage: "clock",
                        description: Text("在测量页保存后，记录会出现在这里")
                    )
                } else {
                    List {
                        ForEach(viewModel.historyStore.records) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.primaryText)
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                                HStack(spacing: 8) {
                                    Text(record.mode.displayName)
                                    if let quality = record.quality {
                                        Text(quality)
                                    }
                                    Spacer()
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.historyStore.remove(viewModel.historyStore.records[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("测量历史")
            .toolbar {
                if !viewModel.historyStore.records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空") {
                            viewModel.historyStore.removeAll()
                        }
                    }
                }
            }
        }
    }
}
