//
//  AlbumPickerView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 相册选择视图 - 卡片下拉手势后弹出，选择目标相册或新建相册
struct AlbumPickerView: View {

    /// 选择相册回调（由 ViewModel 执行添加并关闭弹窗）
    let onSelect: (PhotoAlbum) async -> Void
    /// 新建相册并添加回调
    let onCreate: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PhotoAlbum] = []
    @State private var isLoading = true
    @State private var showCreateAlert = false
    @State private var newAlbumName = ""

    private let photoService = PhotoService()

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("正在加载相册...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if albums.isEmpty {
                    emptyView
                } else {
                    albumList
                }
            }
            .navigationTitle("添加到相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCreateAlert = true
                    } label: {
                        Label("新建相册", systemImage: "plus")
                    }
                }
            }
            .alert("新建相册", isPresented: $showCreateAlert) {
                TextField("相册名称", text: $newAlbumName)
                Button("创建并添加") {
                    Task { await createAlbum() }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .task {
            await loadAlbums()
        }
    }

    // MARK: - Subviews

    private var albumList: some View {
        List {
            Section {
                ForEach(albums) { album in
                    Button {
                        Task { await onSelect(album) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundColor(.blue)

                            Text(album.title)
                                .foregroundColor(.primary)

                            Spacer()

                            Text("\(album.estimatedCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("选择要添加到的相册")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有相册")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("点击右上角「新建相册」创建一个")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadAlbums() async {
        isLoading = true
        let loaded = photoService.fetchUserAlbums()
        await MainActor.run {
            albums = loaded
            isLoading = false
        }
    }

    private func createAlbum() async {
        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newAlbumName = ""
        await onCreate(name)
    }
}

// MARK: - Preview

struct AlbumPickerView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumPickerView(
            onSelect: { _ in },
            onCreate: { _ in }
        )
    }
}
