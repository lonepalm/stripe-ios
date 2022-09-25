//
//  TerminalErrorViewController.swift
//  StripeFinancialConnections
//
//  Created by Krisjanis Gaidis on 9/15/22.
//

import Foundation
import UIKit
@_spi(STP) import StripeUICore

protocol TerminalErrorViewControllerDelegate: AnyObject {
    func terminalErrorViewController(_ viewController: TerminalErrorViewController, didCloseWithError error: Error)
    func terminalErrorViewControllerDidSelectManualEntry(_ viewController: TerminalErrorViewController)
}

final class TerminalErrorViewController: UIViewController {
    
    private let error: Error
    private let allowManualEntry: Bool
    weak var delegate: TerminalErrorViewControllerDelegate?
    
    init(error: Error, allowManualEntry: Bool) {
        self.error = error
        self.allowManualEntry = allowManualEntry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .customBackgroundColor
        navigationItem.hidesBackButton = true
        
        let errorView = ReusableInformationView(
            iconType: .icon, // TODO(kgaidis): add an exclamation circle icon...
            title: STPLocalizedString("Something went wrong", "Title of a screen that shows an error. The error screen appears after user has selected a bank. The error is a generic one: something wrong happened and we are not sure what."),
            subtitle: {
                if allowManualEntry {
                    return STPLocalizedString("Your account can't be linked at this time. Please enter your bank details manually or try again later.", "The subtitle/description of a screen that shows an error. The error is generic: something wrong happened and we are not sure what.")
                } else {
                    return STPLocalizedString("Your account can't be linked at this time. Please try again later.", "The subtitle/description of a screen that shows an error. The error is generic: something wrong happened and we are not sure what.")
                }
            }(),
            primaryButtonConfiguration: {
                // TODO(kgaidis): Stripe.js also checks on "disableManualEntry," but is that dead code?
                if allowManualEntry {
                    return ReusableInformationView.ButtonConfiguration(
                        title: "Enter bank details manually",
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.terminalErrorViewControllerDidSelectManualEntry(self)
                        }
                    )
                } else {
                    return ReusableInformationView.ButtonConfiguration(
                        title: "Close", // TODO(kgaidis): once we localize use String.Localized.close
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.terminalErrorViewController(self, didCloseWithError: self.error)
                        }
                    )
                }
            }()
        )
        view.addAndPinSubviewToSafeArea(errorView)
    }
}
