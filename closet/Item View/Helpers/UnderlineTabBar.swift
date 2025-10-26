struct UnderlineTabBar: View {
    @Binding var selectedTab: String
    let tabs: [String]

    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 20) {
            ForEach(tabs, id: \.self) { tab in
                VStack(spacing: 4) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab)
                            .font(.headline)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }

                    // underline
                    if selectedTab == tab {
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                            .frame(height: 3)
                            .transition(.opacity)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(height: 3)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
