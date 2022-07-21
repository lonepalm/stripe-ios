//
//  InstitutionPicker.swift
//  StripeFinancialConnections
//
//  Created by Vardges Avetisyan on 6/7/22.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeUICore

protocol InstitutionPickerDelegate: AnyObject {
    func institutionPicker(_ picker: InstitutionPicker, didSelect institution: FinancialConnectionsInstitution)
}

class InstitutionPicker: UIViewController {
    
    // MARK: - Properties
    
    private let dataSource: InstitutionDataSource
    
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .minimal // removes black borders
        if #available(iOS 13.0, *) {
            searchBar.searchTextField.textColor = .textSecondary
            // note that increasing the font also dramatically
            // increases the search box height
            searchBar.searchTextField.font = .stripeFont(forTextStyle: .body)
            // this removes the `searchTextField` background color.
            // for an unknown reason, setting the `backgroundColor` to
            // a white color is a no-op
            searchBar.searchTextField.borderStyle = .none
            // use `NSAttributedString` to be able to change the placeholder color
            searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
                string: "Search",
                attributes: [
                    .foregroundColor: UIColor.textDisabled,
                    .font: UIFont.stripeFont(forTextStyle: .body),
                ]
            )
            // change the search icon color..."maagnifyingglass" is SFSymbols
            let searchIcon = UIImage(systemName: "magnifyingglass")?.withTintColor(.textPrimary, renderingMode: .alwaysOriginal)
            searchBar.setImage(searchIcon, for: .search, state: .normal)
        }
        searchBar.layer.borderWidth = 1
        searchBar.layer.cornerRadius = 8
        searchBar.delegate = self
        return searchBar
    }()
    
    private lazy var contentContainerView: UIView = {
        let contentContainerView = UIView()
        contentContainerView.backgroundColor = .clear
        return contentContainerView
    }()
    
    @available(iOS 13.0, *)
    private lazy var featuredInstitutionGridView: FeaturedInstitutionGridView = {
        let featuredInstitutionGridView = FeaturedInstitutionGridView()
        featuredInstitutionGridView.delegate = self
        return featuredInstitutionGridView
    }()
    
    @available(iOS 13.0, *)
    private lazy var institutionSearchTableView: InstitutionSearchTableView = {
        let institutionSearchTableView = InstitutionSearchTableView()
        institutionSearchTableView.delegate = self
        return institutionSearchTableView
    }()
    
    weak var delegate: InstitutionPickerDelegate?
    
    // Only used for iOS12 fallback where we don't ahve the diffable datasource
    private lazy var institutions: [FinancialConnectionsInstitution]? = nil
    
    // MARK: - Debouncing Support

    private var fetchInstitutionsDispatchWorkItem: DispatchWorkItem?
    private var currentFetchInstitutionsDataVersion: Int = 0
    
    // MARK: - Init
    
    init(dataSource: InstitutionDataSource) {
        self.dataSource = dataSource
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.customBackgroundColor
        
        let headerLabel = UILabel()
        headerLabel.text = STPLocalizedString("Select your bank", "The title of the 'Institution Picker' screen where users get to select an institution (ex. a bank like Bank of America).")
        headerLabel.textColor = .textPrimary
        headerLabel.font = .stripeFont(forTextStyle: .subtitle)
        view.addSubview(headerLabel)
        
        setSearchBarBorderColor(isHighlighted: false)
        view.addSubview(searchBar)
        let dismissSearchBarTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOutsideOfSearchBar))
        dismissSearchBarTapGestureRecognizer.delegate = self
        view.addGestureRecognizer(dismissSearchBarTapGestureRecognizer)
        
        if #available(iOS 13.0, *) {
            contentContainerView.addAndPinSubview(featuredInstitutionGridView)
            contentContainerView.addAndPinSubview(institutionSearchTableView)
        }
        view.addSubview(contentContainerView)
        toggleContentContainerViewVisbility()
        
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        let horizontalPadding: CGFloat = 24.0
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            
            searchBar.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: horizontalPadding),
            
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            
            contentContainerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16),
            
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -horizontalPadding),
        ])
        
        fetchFeaturedInstitutions()
    }
    
    private func setSearchBarBorderColor(isHighlighted: Bool) {
        let searchBarBorderColor: UIColor
        if isHighlighted {
            searchBarBorderColor = .textBrand
        } else {
            searchBarBorderColor = .borderNeutral
        }
        searchBar.layer.borderColor = searchBarBorderColor.cgColor
    }
    
    private func toggleContentContainerViewVisbility() {
        if #available(iOS 13.0, *) {
            let isUserCurrentlySearching = searchBar.text?.isEmpty ?? false
            featuredInstitutionGridView.isHidden = !isUserCurrentlySearching
            institutionSearchTableView.isHidden = !featuredInstitutionGridView.isHidden
        }
    }
    
    @IBAction private func didTapOutsideOfSearchBar() {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Data

extension InstitutionPicker {
    
    private func fetchFeaturedInstitutions() {
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        dataSource
            .fetchFeaturedInstitutions()
            .observe(on: DispatchQueue.main) { [weak self] result in
                guard let self = self else { return }
                switch(result) {
                case .success(let institutions):
                    if #available(iOS 13.0, *) {
                        self.featuredInstitutionGridView.loadInstitutions(institutions)
                    }
                case .failure(let error):
                    // TODO(kgaidis): handle featured institution errors
                    print(error)
                }
            }
    }
    
    private func fetchInstitutions(searchQuery: String) {
        fetchInstitutionsDispatchWorkItem?.cancel()
        
        guard !searchQuery.isEmpty else {
            // clear data because search query is empty
            if #available(iOS 13.0, *) {
                institutionSearchTableView.loadInstitutions([])
            }
            return
        }

        let newFetchInstitutionsDispatchWorkItem = DispatchWorkItem(block: { [weak self] in
            guard let self = self else { return }
            
            if #available(iOS 13.0, *) {
                let version = self.currentFetchInstitutionsDataVersion + 1
                
                self.dataSource
                    .fetchInstitutions(searchQuery: searchQuery)
                    .observe(on: DispatchQueue.main) { [weak self] result in
                        guard let self = self else { return }
                        guard self.currentFetchInstitutionsDataVersion < version else {
                            return
                        }
                        self.currentFetchInstitutionsDataVersion = version
                        
                        switch(result) {
                        case .success(let institutions):
                            self.institutionSearchTableView.loadInstitutions(institutions)
                        case .failure(let error):
                            // TODO(kgaidis): handle search error
                            print(error)
                        }
                    }
            }
        })
        
        // TODO(kgaidis): optimize search to only delay if needed...
        
        self.fetchInstitutionsDispatchWorkItem = newFetchInstitutionsDispatchWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.queryDelay, execute: newFetchInstitutionsDispatchWorkItem)
    }
}

// MARK: - UISearchBarDelegate

extension InstitutionPicker: UISearchBarDelegate {
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        setSearchBarBorderColor(isHighlighted: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        setSearchBarBorderColor(isHighlighted: false)
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // TODO(kgaidis): consider showing a loading view
        toggleContentContainerViewVisbility()
        fetchInstitutions(searchQuery: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension InstitutionPicker: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchPoint = touch.location(in: view)
        return !searchBar.frame.contains(touchPoint) && !contentContainerView.frame.contains(touchPoint)
    }
}

// MARK: - FeaturedInstitutionGridViewDelegate

@available(iOS 13.0, *)
extension InstitutionPicker: FeaturedInstitutionGridViewDelegate {
    
    func featuredInstitutionGridView(
        _ view: FeaturedInstitutionGridView,
        didSelectInstitution institution: FinancialConnectionsInstitution
    ) {
        delegate?.institutionPicker(self, didSelect: institution)
    }
}

// MARK: - InstitutionSearchTableViewDelegate

@available(iOS 13.0, *)
extension InstitutionPicker: InstitutionSearchTableViewDelegate {
    
    func institutionSearchTableView(
        _ tableView: InstitutionSearchTableView,
        didSelectInstitution institution: FinancialConnectionsInstitution
    ) {
        delegate?.institutionPicker(self, didSelect: institution)
    }
}

// MARK: - Constants

extension InstitutionPicker {
    enum Constants {
      static let queryDelay = TimeInterval(0.2)
  }
}
