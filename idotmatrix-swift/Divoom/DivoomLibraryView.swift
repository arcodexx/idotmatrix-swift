import SwiftUI

struct DivoomLibraryView: View {
    @ObservedObject var client = DivoomClient.shared
    @ObservedObject var viewModel = ViewModel.shared

    @State private var email = ""
    @State private var password = ""
    @State private var showingLogin = false
    @State private var loginError: String?
    @State private var isLoggingIn = false

    @State private var selectedCategory: DivoomCategory = .recommend
    @State private var files: [DivoomFile] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var errorMsg: String?
    @State private var hasMorePages = true

    // Grid layout
    let columns = [
        GridItem(.adaptive(minimum: 160))
    ]

    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Divoom Library")
                    .bold()

                Spacer()

                if client.isLoggedIn {
                   // Picker Temporarily Disabled due to Format 8 issues
                   // Picker("Category", selection: $selectedCategory) {
                   //    ForEach(DivoomCategory.allCases) { category in
                   //        Text(category.title).tag(category)
                   //    }
                   // }
                   // .pickerStyle(MenuPickerStyle())
                   // .frame(width: 150)
                   Text("Recommended")
                       .font(.subheadline)
                       .foregroundStyle(.secondary)
                }
            }
            .padding()

            if !client.isLoggedIn {
                // Login View
                VStack(spacing: 20) {
                    Text("Login to Divoom")
                        .font(.title)

                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)

                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)

                    if let err = loginError {
                        Text(err)
                            .foregroundColor(.red)
                    }

                    Button(action: login) {
                        if isLoggingIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Login")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoggingIn || email.isEmpty || password.isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Gallery View
                ScrollView {
                    if isLoading && files.isEmpty {
                        ProgressView("Loading...")
                            .padding()
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(files) { file in
                                DivoomGalleryItemView(file: file, viewModel: viewModel)
                            }

                            // Pagination trigger
                            if !files.isEmpty && !isLoading {
                                Color.clear
                                    .frame(height: 20)
                                    .onAppear {
                                        loadMore()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onChange(of: selectedCategory) { _ in
            reloadGallery()
        }
        .task {
            // If already logged in, load gallery
             if client.isLoggedIn {
                 reloadGallery()
             }
        }
    }
    // MARK: - Actions

    func login() {
        isLoggingIn = true
        loginError = nil
        Task {
            do {
                _ = try await client.login(email: email, password: password)
                await MainActor.run {
                    isLoggingIn = false
                    reloadGallery()
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    loginError = error.localizedDescription
                }
            }
        }
    }

    func reloadGallery() {
        files = []
        currentPage = 1
        hasMorePages = true
        loadMore()
    }

    func loadMore() {
        guard !isLoading && hasMorePages else { return }
        isLoading = true

        Task {
            do {
                let newFiles = try await client.fetchFiles(category: selectedCategory, page: currentPage)
                await MainActor.run {
                    if newFiles.isEmpty {
                        hasMorePages = false
                    } else {
                        files.append(contentsOf: newFiles)
                        currentPage += 1
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isLoading = false
                    print("Gallery error: \(error)")
                }
            }
        }
    }
}

struct DivoomGalleryItemView: View {
    let file: DivoomFile
    @ObservedObject var viewModel: ViewModel

    @State private var previewUrl: URL?
    @State private var isConverting = false
    @State private var errorMsg: String?
    @State private var isSaved = false

    var body: some View {
        VStack {
            // Preview / Placeholder Area
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 160)
                    .cornerRadius(8)

                if let previewUrl = previewUrl {
                    // Show Animated GIF
                    GifView(url: previewUrl)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Loading / Placeholder / Error
                    if errorMsg != nil {
                         Image(systemName: "exclamationmark.triangle")
                             .foregroundStyle(.gray)
                    } else {
                         VStack {
                              ProgressView()
                                  .controlSize(.small)
                         }
                    }
                }
            }
            .onAppear { // Auto load
                if previewUrl == nil {
                    loadPreview()
                }
            }

            Text(file.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            if previewUrl != nil {
                HStack {
                    Button("Send") {
                        sendToDevice()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // TODO: Add Save Button
                    if isSaved {
                        Label("Saved", systemImage: "checkmark")
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().stroke(Color.green))
                            .controlSize(.small)
                            .font(.caption)
                    } else {
                        Button("Save") {
                            saveToAssets()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .frame(width: 180)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
    }

    func saveToAssets() {
        guard let url = previewUrl, let data = try? Data(contentsOf: url) else { return }
        AssetManager.shared.saveGif(name: file.fileName, data: data)
        withAnimation {
            isSaved = true
        }
    }

    func loadPreview() {
        guard !isConverting else { return }
        isConverting = true

        Task {
            // Use constructed URL fallback
            guard let url = file.constructedUrl else {
                isConverting = false
                return
            }

            if let convertedUrl = await viewModel.convertDivoomFile(url: url) {
                await MainActor.run {
                    self.previewUrl = convertedUrl
                    self.isConverting = false
                }
            } else {
                 await MainActor.run {
                     self.isConverting = false
                     self.errorMsg = "Failed" // Set Error
                 }
            }
        }
    }

    func sendToDevice() {
        guard let url = previewUrl else { return }
        Task {
            if let data = try? Data(contentsOf: url) {
                await viewModel.sendGif(data)
            }
        }
    }
}
