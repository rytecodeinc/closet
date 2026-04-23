//
//  OutfitFullScreenView.swift
//  closet
//
//  Fullscreen pager for outfit collage + worn photo (skips missing slots).
//

import SwiftUI

struct OutfitFullScreenView: View {
    let collageImage: UIImage?
    let wornImage: UIImage?
    @Binding var selectedPageIndex: Int
    @Binding var isPresented: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    private var availableImages: [(image: UIImage, label: String)] {
        var images: [(image: UIImage, label: String)] = []
        if let collage = collageImage {
            images.append((collage, "Collage"))
        }
        if let worn = wornImage {
            images.append((worn, "Photo"))
        }
        return images
    }

    var body: some View {
        ZStack {
            Color(red: 247/255, green: 247/255, blue: 247/255)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            if availableImages.isEmpty {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No images available")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 16)
                }
            } else {
                TabView(selection: $selectedPageIndex) {
                    ForEach(Array(availableImages.enumerated()), id: \.offset) { index, imageData in
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                Image(uiImage: imageData.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(.white)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .scaleEffect(currentScale * gestureScale)
                                    .gesture(
                                        MagnificationGesture()
                                            .updating($gestureScale) { value, state, _ in
                                                state = value
                                            }
                                    )

                                Text(imageData.label)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .padding(.bottom, 60)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isPresented = false
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .animation(nil, value: selectedPageIndex)
                .onChange(of: selectedPageIndex) { _, _ in
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        currentScale = 1.0
                    }
                }
                .onAppear {
                    let n = availableImages.count
                    guard n > 0 else { return }
                    if selectedPageIndex < 0 || selectedPageIndex >= n {
                        selectedPageIndex = min(max(0, selectedPageIndex), n - 1)
                    }
                }
                .onChange(of: availableImages.count) { _, newCount in
                    guard newCount > 0 else { return }
                    if selectedPageIndex >= newCount {
                        selectedPageIndex = newCount - 1
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                }

                if availableImages.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<availableImages.count, id: \.self) { index in
                                Circle()
                                    .fill(selectedPageIndex == index ? Color.black : Color.gray.opacity(0.4))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .statusBarHidden()
        .offset(y: dragOffset.height)
        .opacity(1.0 - abs(dragOffset.height) / UIScreen.main.bounds.height * 0.5)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) * 2 {
                        if value.translation.height > 0 {
                            dragOffset = value.translation
                        }
                    }
                }
                .onEnded { value in
                    let threshold = min(100, UIScreen.main.bounds.height * 0.3)
                    if value.translation.height > threshold || value.predictedEndTranslation.height > UIScreen.main.bounds.height * 0.5 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onChange(of: isPresented) { _, newValue in
            if !newValue {
                dragOffset = .zero
            }
        }
    }
}
