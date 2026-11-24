//
// BodyProgressPhotos.swift
// Tempo
//
// The photo half of Body progress: a thumbnail, the full photo with a delete
// button, two photos side by side, and the camera. The photos live as files on
// this phone (ProgressPhotoStore); nothing here uploads them.
//

import SwiftUI
import UIKit

// MARK: - ProgressPhotoThumbnail

/// One photo as a small portrait tile. The thumbnail is decoded off the main
/// thread, so a long list scrolls smoothly.
struct ProgressPhotoThumbnail: View {
    let photo: ProgressPhoto
    let store: ProgressPhotoStore
    var maxPixel: CGFloat = 400

    @State
    private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Tide.fill
                }
            }
            .clipShape(.rect(cornerRadius: Tide.controlRadius))
            .task(id: photo.id) {
                let store = store
                let photo = photo
                let pixels = maxPixel
                image = await Task.detached(priority: .utility) {
                    store.thumbnail(for: photo, maxPixel: pixels)
                }.value
            }
    }
}

// MARK: - ProgressPhotoViewer

/// One photo at full size, with the way to delete it. Deleting asks first:
/// the file is only on this phone, so it cannot be brought back.
struct ProgressPhotoViewer: View {
    let photo: ProgressPhoto
    let store: ProgressPhotoStore
    let onDelete: (ProgressPhoto) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var image: UIImage?
    @State
    private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Tide.s4) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: Tide.tileRadius))
                        .accessibilityLabel("Progress photo from \(photo.date.formatted(date: .long, time: .omitted))")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(photo.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(Tide.edge)
            .tidePage()
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete photo", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                    .accessibilityIdentifier("progress-photo-delete")
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    onDelete(photo)
                    dismiss()
                }
            } message: {
                Text("It is only on this phone, so it can't be brought back.")
            }
            .task {
                let store = store
                let photo = photo
                image = await Task.detached(priority: .userInitiated) {
                    store.image(for: photo)
                }.value
            }
        }
        .accessibilityIdentifier("progress-photo-viewer")
    }
}

// MARK: - ProgressPhotoCompare

/// Two photos side by side. It opens on the oldest and the newest; each side
/// can be switched to any other date.
struct ProgressPhotoCompare: View {
    /// Newest first, as the store lists them.
    let photos: [ProgressPhoto]
    let store: ProgressPhotoStore

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var earlierID: String?
    @State
    private var laterID: String?

    private var earlier: ProgressPhoto? {
        photos.first { $0.id == earlierID } ?? photos.last
    }

    private var later: ProgressPhoto? {
        photos.first { $0.id == laterID } ?? photos.first
    }

    /// "56 days apart", or nothing when both sides are the same photo.
    private var gap: String? {
        guard let earlier, let later, earlier.id != later.id else {
            return nil
        }
        let days = abs(Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: earlier.date), to: Calendar.current.startOfDay(for: later.date)
        ).day ?? 0)
        return days == 1 ? "1 day apart" : "\(days) days apart"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tide.s4) {
                    HStack(alignment: .top, spacing: Tide.s3) {
                        side(title: "Earlier", photo: earlier, selection: $earlierID)
                        side(title: "Later", photo: later, selection: $laterID)
                    }
                    if let gap {
                        Text(gap)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s8)
            }
            .scrollIndicators(.hidden)
            .tidePage()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("progress-photo-compare")
    }

    private func side(title: String, photo: ProgressPhoto?, selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(title).tideLabel(Tide.text3)
            Menu {
                ForEach(photos) { option in
                    Button(option.date.formatted(date: .abbreviated, time: .omitted)) {
                        selection.wrappedValue = option.id
                    }
                }
            } label: {
                HStack(spacing: Tide.s1) {
                    Text(photo?.date.formatted(date: .abbreviated, time: .omitted) ?? "--")
                        .font(Tide.bodyStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Tide.label)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
            }
            .buttonStyle(.tideGlass)
            .accessibilityLabel("\(title) photo date")
            if let photo {
                ProgressPhotoThumbnail(photo: photo, store: store, maxPixel: 900)
                    .accessibilityLabel("\(title) photo from \(photo.date.formatted(date: .long, time: .omitted))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - ProgressPhotoCamera

/// The system camera, for one photo. It hands the picture back and closes.
struct ProgressPhotoCamera: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    /// False on a simulator and on a device without a camera.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
