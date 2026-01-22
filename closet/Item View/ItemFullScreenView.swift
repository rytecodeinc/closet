//
//  ItemFullScreenView.swift
//  closet
//
//  Created by Dan Warner on 12/6/25.
//

import SwiftUI

struct ItemFullScreenView: View {
    let frontImage: UIImage?
    let backImage: UIImage?
    let wornImage: UIImage?
    let initialIndex: Int
    @Binding var isPresented: Bool
    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    
    init(frontImage: UIImage?, backImage: UIImage?, wornImage: UIImage?, initialIndex: Int, isPresented: Binding<Bool>) {
        self.frontImage = frontImage
        self.backImage = backImage
        self.wornImage = wornImage
        self.initialIndex = initialIndex
        self._isPresented = isPresented
        
        // Calculate available images to determine valid initial index
        var imageCount = 0
        if frontImage != nil { imageCount += 1 }
        if backImage != nil { imageCount += 1 }
        if wornImage != nil { imageCount += 1 }
        
        // Clamp initial index to valid range
        let clampedIndex = min(max(0, initialIndex), max(0, imageCount - 1))
        self._currentIndex = State(initialValue: clampedIndex)
    }
    
    // Computed property to get available images in order
    private var availableImages: [(image: UIImage, label: String)] {
        var images: [(image: UIImage, label: String)] = []
        
        if let front = frontImage {
            images.append((front, "Front"))
        }
        if let back = backImage {
            images.append((back, "Back"))
        }
        if let worn = wornImage {
            images.append((worn, "Worn"))
        }
        
        return images
    }
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            if availableImages.isEmpty {
                // No images available
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No images available")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 16)
                }
            } else {
                // Image gallery with TabView for swiping
                TabView(selection: $currentIndex) {
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
                                            .onEnded { value in
                                                // Use transaction to ensure smooth animation when gestureScale resets
                                                var transaction = Transaction(animation: .spring(response: 0.3, dampingFraction: 0.8))
                                                transaction.disablesAnimations = false
                                                withTransaction(transaction) {
                                                    // gestureScale will automatically reset to 1.0 with smooth animation
                                                }
                                            }
                                    )
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: gestureScale)
                                
                                // Caption label at bottom
                                Text(imageData.label)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                //    .background(Color.gray.opacity(0.1))
                                //    .cornerRadius(8)
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
                .onChange(of: currentIndex) { _ in
                    // Reset scale when switching images
                    currentScale = 1.0
                }
                
                // Subtle dismiss button in top-right corner
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
                
                // Page indicator at bottom
                if availableImages.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<availableImages.count, id: \.self) { index in
                                Circle()
                                    .fill(currentIndex == index ? Color.black : Color.gray.opacity(0.4))
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
                    // Only respond to vertical drags (more vertical than horizontal)
                    // Require at least 2:1 ratio to avoid interfering with horizontal swipes
                    if abs(value.translation.height) > abs(value.translation.width) * 2 {
                        // Only allow downward swipes
                        if value.translation.height > 0 {
                            dragOffset = value.translation
                        }
                    }
                }
                .onEnded { value in
                    // Dismiss if swiped down more than 100 points or 30% of screen height
                    let threshold = min(100, UIScreen.main.bounds.height * 0.3)
                    if value.translation.height > threshold || value.predictedEndTranslation.height > UIScreen.main.bounds.height * 0.5 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    } else {
                        // Spring back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onChange(of: isPresented) { newValue in
            // Reset drag offset when view is dismissed
            if !newValue {
                dragOffset = .zero
            }
        }
    }
}

