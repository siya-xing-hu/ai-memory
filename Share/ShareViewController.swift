import UIKit
import Social
import SwiftData

class ShareViewController: UIViewController {
    private let textView = UITextView()
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSharedContent()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let navBar = UINavigationBar()
        let navItem = UINavigationItem(title: "分享到 AI Memory")
        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navItem.leftBarButtonItem = cancel
        navBar.setItems([navItem], animated: false)

        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8

        saveButton.setTitle("保存", for: .normal)
        saveButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        saveButton.backgroundColor = .systemBlue
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 10
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [textView, saveButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        navBar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(navBar)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            saveButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func loadSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else { return }

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                attachment.loadItem(forTypeIdentifier: "public.plain-text") { [weak self] item, _ in
                    let text = (item as? String) ?? ""
                    DispatchQueue.main.async {
                        self?.textView.text = text
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier("public.url") {
                attachment.loadItem(forTypeIdentifier: "public.url") { [weak self] item, _ in
                    let text = (item as? URL)?.absoluteString ?? ""
                    DispatchQueue.main.async {
                        self?.textView.text = text
                    }
                }
            }
        }
    }

    @objc private func saveTapped() {
        guard !textView.text.isEmpty else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        do {
            let schema = Schema([DayChat.self, ChatMessage.self, TopicSummary.self])
            let config = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier("group.com.app.memory")
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let today = Calendar.current.startOfDay(for: Date())
            let descriptor = FetchDescriptor<DayChat>(
                predicate: #Predicate { $0.date == today }
            )
            let dayChat: DayChat
            if let existing = try context.fetch(descriptor).first {
                dayChat = existing
            } else {
                dayChat = DayChat(date: today)
                context.insert(dayChat)
            }

            let message = ChatMessage(role: .user, content: textView.text)
            context.insert(message)
            dayChat.messages.append(message)
            dayChat.updatedAt = Date()

            try context.save()
        } catch {
            print("Save failed: \(error)")
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.app.memory.share", code: 0))
    }
}
