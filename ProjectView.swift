import SwiftUI

struct ProjectView: View {
    // 模拟文件树数据
    let files: [ProjectFile] = [
        ProjectFile(name: "GameProject", isDirectory: true, children: [
            ProjectFile(name: "main.lua", isDirectory: false, children: nil),
            ProjectFile(name: "PlayerController.lua", isDirectory: false, children: nil),
            ProjectFile(name: "Assets", isDirectory: true, children: [
                ProjectFile(name: "texture.png", isDirectory: false, children: nil)
            ])
        ])
    ]
    
    var body: some View {
        NavigationView {
            List(files, children: \.children) { file in
                HStack {
                    Image(systemName: file.isDirectory ? "folder" : "doc.text")
                        .foregroundColor(file.isDirectory ? .blue : .gray)
                    Text(file.name)
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("我的项目")
            .background(Color.black.ignoresSafeArea())
        }
    }
}
