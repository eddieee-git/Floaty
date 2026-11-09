import SwiftUI

/// 메뉴 안에 넣는 색 목록. 이름 앞에 색 동그라미를 두고 지금 색에 체크한다.
/// `selected`가 nil이면(여러 색이 섞여 있으면) 아무것에도 체크하지 않는다.
struct PaletteMenuItems: View {
    let selected: Int?
    let choose: (Int) -> Void

    var body: some View {
        Picker(selection: Binding(get: { selected ?? -1 }, set: choose)) {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Label {
                    Text(L(Palette.colors[i].name))
                } icon: {
                    Image(nsImage: Palette.swatch(i))
                }
                .tag(i)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
