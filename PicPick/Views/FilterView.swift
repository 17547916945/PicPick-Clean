//
//  FilterView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI

/// 综合筛选视图（日期 + 媒体类型）
struct FilterView: View {

    // 日期筛选
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isDateFilterEnabled: Bool

    // 媒体类型筛选
    @Binding var selectedMediaType: MediaType

    let onApply: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false

    var body: some View {
        NavigationView {
            Form {
                // 媒体类型选择
                mediaTypeSection

                // 日期筛选
                dateFilterSection

                if isDateFilterEnabled {
                    dateRangeSection
                    dateInfoSection
                    quickSelectSection
                }
            }
            .navigationTitle("筛选")
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

    private var mediaTypeSection: some View {
        Section {
            ForEach(MediaType.allCases) { type in
                Button {
                    selectedMediaType = type
                } label: {
                    HStack(spacing: 12) {
                        Text(type.emoji)
                            .font(.title3)

                        Text(type.rawValue)
                            .foregroundColor(.primary)

                        Spacer()

                        if selectedMediaType == type {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            Text("媒体类型")
        } footer: {
            Text("选择要查看的媒体类型")
                .font(.caption)
        }
    }

    private var dateFilterSection: some View {
        Section {
            Toggle("启用日期筛选", isOn: $isDateFilterEnabled)
                .tint(.blue)
        } header: {
            Text("日期范围")
        }
    }

    private var dateRangeSection: some View {
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
        } footer: {
            Text("筛选此日期范围内的媒体")
                .font(.caption)
        }
    }

    private var dateInfoSection: some View {
        Section {
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
    }

    private var quickSelectSection: some View {
        Section {
            VStack(spacing: 12) {
                quickSelectThisMonthButton()
                quickSelectButton(title: "最近 7 天", days: 7)
                quickSelectButton(title: "最近 30 天", days: 30)
                quickSelectButton(title: "最近 90 天", days: 90)
                quickSelectButton(title: "最近一年", days: 365)
            }
        } header: {
            Text("快速选择")
        }
    }

    /// 「本月」快捷按钮 - 恢复默认的当月整理队列
    private func quickSelectThisMonthButton() -> some View {
        Button {
            let calendar = Calendar.current
            let startOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: Date())
            ) ?? Date()
            startDate = startOfMonth
            endDate = Date()
            isDateFilterEnabled = true
        } label: {
            HStack {
                Text("本月（默认）")
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
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

                Text("正在加载...")
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

    private func setQuickRange(days: Int) {
        let calendar = Calendar.current
        endDate = Date()
        startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        isDateFilterEnabled = true
    }
}

// MARK: - Preview

struct FilterView_Previews: PreviewProvider {
    static var previews: some View {
        FilterView(
            startDate: .constant(Date()),
            endDate: .constant(Date()),
            isDateFilterEnabled: .constant(true),
            selectedMediaType: .constant(.allPhotos),
            onApply: {}
        )
    }
}
