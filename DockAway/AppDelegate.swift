import Cocoa
import ServiceManagement
import Sparkle

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    var isQuitting = false
    private var statusItem: NSStatusItem!
    private var dockWatcher: DockWatcher!
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 APP LAUNCHED")
        NSApp.setActivationPolicy(.accessory)
        
        //Initialize Sparkle
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        setupMenuBar()
        requestAccessibilityPermission()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "Imageset")
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Status: Detecting…", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.tag = 200
        launchAtLogin.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        
        // --- SPARKLE UPDATE MENU ITEM  ---
                let updateMenuItem = NSMenuItem(
                    title: "Check for Updates...",
                    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                    keyEquivalent: ""
                )
        
        // Safety check to ensure we have a controller
                if let controller = self.updaterController {
                    updateMenuItem.target = controller
                    updateMenuItem.isEnabled = true
                } else {
                    // If it's nil, we initialize it right here as a fallback
                    self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
                    updateMenuItem.target = self.updaterController
                    updateMenuItem.isEnabled = true
                }
                
                menu.addItem(updateMenuItem)
                // ---

        menu.addItem(NSMenuItem(title: "About DockAway", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusItem.menu?.item(withTag: 100)?.title = "Status: \(text)"
        }
    }

    // MARK: - Launch at Login

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("⚠️ Launch at login error: \(error)")
        }
        statusItem.menu?.item(withTag: 200)?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    // MARK: - About

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        
        // 1. Create a paragraph style and set it to center alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        // 2. Create the string with an extra newline (\n\n) for spacing
        let creditsText = "Copyright (C) 2026 Abdullah Khairaddin\n\nHides the Dock when apps are on screen and it reappears on an empty desktop ."
        
        // 3. Apply the paragraph style to the attributed string
        let attributedCredits = NSAttributedString(
            string: creditsText,
            attributes: [.paragraphStyle: paragraphStyle]
        )
        
        // 4. Pass the updated attributed string to the options panel
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "DockAway",
            NSApplication.AboutPanelOptionKey.version: "1.0",
            NSApplication.AboutPanelOptionKey.credits: attributedCredits
        ])
    }

    // MARK: - First Launch

    private func ensureDockAwayIsOn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let defaults = UserDefaults(suiteName: "com.apple.dock")
            let isAlreadyOn = defaults?.bool(forKey: "autohide") ?? false
            if !isAlreadyOn {
                self.dockWatcher.simulateOptionCommandDPublic()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.dockWatcher.resetState()
            }
        }
    }

    private func showWelcomeIfNeeded() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        guard !hasLaunchedBefore else { return }
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Welcome to DockAway 👋"
            alert.informativeText = "Your Dock will now automatically appear when you are on an empty desktop and hides when an app occupies the screen.\n\n• Toggle Launch at Login from the menu bar.\n• The app runs silently and efficiently in the background.\n\nEnjoy your Extra Real Estate!"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Awesome!")
            alert.runModal()
        }
    }

    // MARK: - Accessibility

    private func requestAccessibilityPermission() {
        if AXIsProcessTrusted() {
            dockWatcher = DockWatcher()
            ensureDockAwayIsOn()
            dockWatcher.start()
            showWelcomeIfNeeded()
        } else {
            let alert = NSAlert()
            
            // 1. Keep the main header clean
            alert.messageText = "But First ☝️"
            
            // 2. Put both the subtitle and body in the informative text to bypass the layout gap
            alert.informativeText = "Accessibility Permission is Required:\nDockAway is requesting accessibility permission from system settings in order to detect desktop app occupancy status."
            alert.alertStyle = .informational
            
            // Buttons populate right-to-left
            alert.addButton(withTitle: "Allow Access")
            alert.addButton(withTitle: "Quit")
            
            // 3. Force layout generation so we can style the subview text fields directly
            alert.layout()
            
            // 4. Find the informative text field and make the first line bold with tight spacing
            if let contentView = alert.window.contentView {
                func findTextField(in view: NSView, matching text: String) -> NSTextField? {
                    if let textField = view as? NSTextField, textField.stringValue.contains(text) {
                        return textField
                    }
                    for subview in view.subviews {
                        if let found = findTextField(in: subview, matching: text) {
                            return found
                        }
                    }
                    return nil
                }
                
                if let informativeTextField = findTextField(in: contentView, matching: "Accessibility Permission is Required:") {
                    let fullString = informativeTextField.stringValue as NSString
                    let targetLine = "Accessibility Permission is Required:"
                    let firstLineRange = fullString.range(of: targetLine)
                    let remainingRange = NSRange(location: firstLineRange.length, length: fullString.length - firstLineRange.length)
                    
                    let attributedString = NSMutableAttributedString(string: informativeTextField.stringValue)
                    
                    // Styling the subtitle line (Bold & Dark)
                    attributedString.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 11), range: firstLineRange)
                    attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: firstLineRange)
                    
                    // Styling the body text line (Regular & Muted)
                    attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: remainingRange)
                    attributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: remainingRange)
                    
                    // Adjust paragraph system settings for clean line-heights
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineSpacing = 2
                    paragraphStyle.paragraphSpacing = 4
                    attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: fullString.length))
                    
                    informativeTextField.attributedStringValue = attributedString
                }
            }
            
            // Handle button response
            if alert.runModal() == .alertFirstButtonReturn {
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
                AXIsProcessTrustedWithOptions(options)
                waitForAccessibility()
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    private func waitForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if AXIsProcessTrusted() {
                print("✅ Accessibility granted — starting detector")
                self.dockWatcher = DockWatcher()
                self.ensureDockAwayIsOn()
                self.dockWatcher.start()
                self.showWelcomeIfNeeded()
            } else {
                self.waitForAccessibility()
            }
        }
    }

    // MARK: - Quit

    @objc private func quit() {
        isQuitting = true
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        defaults?.set(false, forKey: "autohide")
        defaults?.synchronize()

        Thread.sleep(forTimeInterval: 0.3)

        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Dock"]
        try? task.run()

        Thread.sleep(forTimeInterval: 0.5)
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup already handled in quit()
    }
}
