//
//  DateFilterView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI

/// 日期范围筛选视图
struct DateFilterView: View {

    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isFilterEnabled: Bool

    let onApply: () async -> Void
    let onClear: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("启用日期筛选", isOn: $isFilterEnabled)
                        .tint(.blue)
                } header: {
                    Text("筛选设置")
                }

                if isFilterEnabled {
                    Section {
                        DatePicker(
                            "开始日期",
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)

                        DatePicker(
                            "结束日期",
                            selection: $endDate,
                            in: startDate...Date(),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                    } header: {
                        Text("日期范围")
                    } footer: {
                        Text("将筛选此日期范围内的所有照片")
                            .font(.caption)
                    }

                    Section {
                        dateRangeInfo
                    } header: {
                        Text("筛选信息")
                    }

                    Section {
                        quickSelectButtons
                    } header: {
                        Text("快速选择")
                    }
                }
            }
            .navigationTitle("日期筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            await applyFilter()
                        }
                    }
                    .disabled(isApplying)
                }

                ToolbarItem(placement: .bottomBar) {
                    if isFilterEnabled {
                        Button(role: .destructive) {
                            Task {
                                await clearFilter()
                            }
                        } label: {
                            Label("清除筛选", systemImage: "xmark.circle")
                        }
                        .disabled(isApplying)
                    }
                }
            }
            .disabled(isApplying)
            .overlay {
                if isApplying {
                    loadingOverlay
                }
            }
        }
    }

    // MARK: - Subviews

    private var dateRangeInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text("时间范围：\(daysBetween) 天")
                    .font(.subheadline)
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                Text(formatDateRange)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var quickSelectButtons: some View {
        VStack(spacing: 12) {
            quickSelectButton(title: "最近 7 天", days: 7)
            quickSelectButton(title: "最近 30 天", days: 30)
            quickSelectButton(title: "最近 90 天", days: 90)
            quickSelectButton(title: "最近一年", days: 365)
        }
    }

    private func quickSelectButton(title: String, days: Int) -> some View {
        Button {
            setQuickRange(days: days)
        } label: {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("正在加载照片...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }

    // MARK: - Computed Properties

    private var daysBetween: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return (components.day ?? 0) + 1
    }

    private var formatDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        return "\(start) - \(end)"
    }

    // MARK: - Actions

    private func applyFilter() async {
        isApplying = true

        await onApply()

        await MainActor.run {
            isApplying = false
            dismiss()
        }
    }

    private func clearFilter() async {
        isApplying = true
        isFilterEnabled = false

        await onClear()

        await MainActor.run {
            isApplying = false
            dismiss()
        }
    }

    private func setQuickRange(days: Int) {
        let calendar = Calendar.current
        endDate = Date()
        startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        isFilterEnabled = true
    }
}

// MARK: - Preview

struct DateFilterView_Previews: PreviewProvider {
    static var previews: some View {
        DateFilterView(
            startDate: .constant(Date()),
            endDate: .constant(Date()),
            isFilterEnabled: .constant(true),
            onApply: {},
            onClear: {}
        )
    }
}
