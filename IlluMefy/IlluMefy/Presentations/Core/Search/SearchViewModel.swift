//
//  SearchViewModel.swift
//  IlluMefy
//
//  Created by Assistant on 2025/06/15.
//

import Foundation
import Combine

/// 検索ViewModel
@MainActor
final class SearchViewModel: SearchViewModelProtocol {
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published private(set) var suggestions: [Tag] = []
    @Published private(set) var selectedTags: [Tag] = []
    @Published private(set) var state: SearchState = .initial
    @Published private(set) var searchHistory: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var totalCount = 0
    
    // MARK: - Private Properties
    private let searchTagsByNameUseCase: SearchTagsByNameUseCaseProtocol
    private let searchCreatorsByTagsUseCase: SearchCreatorsByTagsUseCaseProtocol
    private let saveSearchHistoryUseCase: SaveSearchHistoryUseCase
    private let getSearchHistoryUseCase: GetSearchHistoryUseCase
    private let clearSearchHistoryUseCase: ClearSearchHistoryUseCase
    private let tagSuggestionService = TagSuggestionService()
    
    private var cancellables = Set<AnyCancellable>()
    private var currentCreators: [Creator] = []
    private var currentOffset = 0
    private let pageSize = 20
    private var allTags: [Tag] = []
    
    // MARK: - Initialization
    init(
        searchTagsByNameUseCase: SearchTagsByNameUseCaseProtocol,
        searchCreatorsByTagsUseCase: SearchCreatorsByTagsUseCaseProtocol,
        saveSearchHistoryUseCase: SaveSearchHistoryUseCase,
        getSearchHistoryUseCase: GetSearchHistoryUseCase,
        clearSearchHistoryUseCase: ClearSearchHistoryUseCase
    ) {
        self.searchTagsByNameUseCase = searchTagsByNameUseCase
        self.searchCreatorsByTagsUseCase = searchCreatorsByTagsUseCase
        self.saveSearchHistoryUseCase = saveSearchHistoryUseCase
        self.getSearchHistoryUseCase = getSearchHistoryUseCase
        self.clearSearchHistoryUseCase = clearSearchHistoryUseCase
        
        setupBindings()
        loadSearchHistory()
        loadAllTags()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // 検索テキストのオートコンプリート（リアルタイム検索のためdebounceを短縮）
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.updateSuggestions(query: query)
            }
            .store(in: &cancellables)
        
        // 選択されたタグの変更を監視して検索実行
        $selectedTags
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSearch()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadSearchHistory() {
        Task {
            do {
                let history = try await getSearchHistoryUseCase.execute()
                await MainActor.run {
                    self.searchHistory = history
                }
            } catch {
            }
        }
    }
    
    private func loadAllTags() {
        Task {
            await loadAllTagsAsync()
        }
    }
    
    private func loadAllTagsAsync() async {
        do {
            // 全タグを取得してキャッシュ
            let result = try await searchTagsByNameUseCase.execute(
                request: SearchTagsByNameUseCaseRequest(
                    andQuery: "",
                    orQuery: "",
                    offset: 0,
                    limit: 1000 // 大きな値で全タグを取得
                )
            )
            await MainActor.run {
                self.allTags = result.tags
            }
        } catch {
        }
    }
    
    private func updateSuggestions(query: String) {
        suggestions = tagSuggestionService.generateSuggestions(
            query: query,
            allTags: allTags,
            selectedTags: selectedTags
        )
    }
    
    private func performSearch() async {
        // 選択されたタグがない場合は初期状態に戻す
        guard !selectedTags.isEmpty else {
            state = .initial
            currentCreators = []
            hasMore = false
            return
        }
        
        await search()
    }
    
    // MARK: - Public Methods
    func search() async {
        
        isLoading = true
        state = .searching
        currentOffset = 0
        currentCreators = []
        
        await searchCreatorsBySelectedTags()
        
        isLoading = false
    }
    
    private func searchCreatorsBySelectedTags() async {
        do {
            // 選択されたタグを全て含むクリエイターを検索（AND検索）
            let tagIds = selectedTags.map { $0.id }
            
            let request = SearchCreatorsByTagsUseCaseRequest(
                tagIds: tagIds,
                searchMode: .all,
                offset: currentOffset,
                limit: pageSize
            )
            let result = try await searchCreatorsByTagsUseCase.execute(request: request)
            
            // 検索履歴に保存
            let searchQuery = buildSearchQueryForHistory()
            if !searchQuery.isEmpty {
                try await saveSearchHistoryUseCase.execute(query: searchQuery)
                loadSearchHistory()
            }
            
            currentCreators = result.creators
            hasMore = result.hasMore
            totalCount = result.totalCount
            
            if result.creators.isEmpty {
                state = .empty
            } else {
                state = .loadedCreators(result.creators)
            }
        } catch let error as SearchCreatorsByTagsUseCaseError {
            state = .error(error.title, error.message)
        } catch {
            state = .error(L10n.Search.Error.creatorSearchTitle, L10n.Search.Error.creatorSearchMessage)
        }
    }
    
    private func buildSearchQueryForHistory() -> String {
        return selectedTags.map { $0.displayName }.joined(separator: ",")
    }
    
    func loadMore() async {
        guard hasMore && !isLoading else { return }
        
        isLoading = true
        currentOffset += pageSize
        
        do {
            let tagIds = selectedTags.map { $0.id }
            let request = SearchCreatorsByTagsUseCaseRequest(
                tagIds: tagIds,
                searchMode: .all,
                offset: currentOffset,
                limit: pageSize
            )
            let result = try await searchCreatorsByTagsUseCase.execute(request: request)
            
            // 既存の結果に追加
            currentCreators.append(contentsOf: result.creators)
            hasMore = result.hasMore
            state = .loadedCreators(currentCreators)
            
        } catch {
            // エラーは無視してローディングだけ停止
        }
        
        isLoading = false
    }
    
    func clearSearch() {
        searchText = ""
        selectedTags = []
        suggestions = []
        state = .initial
        currentCreators = []
        hasMore = false
        currentOffset = 0
        totalCount = 0
    }
    
    func selectFromHistory(_ query: String) {
        // 履歴からの復元は簡略化のため省略
        // 必要に応じて実装
    }
    
    func addTagsFromHistory(_ query: String) {
        // 履歴クエリはカンマ区切りのタグ名の形式
        let tagNames = query.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        var tagsToAdd: [Tag] = []
        for tagName in tagNames {
            // タグ名に一致するタグを検索
            if let matchingTag = allTags.first(where: { tag in
                tag.displayName == tagName
            }) {
                // 重複チェック
                if !selectedTags.contains(where: { $0.id == matchingTag.id }) {
                    tagsToAdd.append(matchingTag)
                }
            }
        }
        
        // テキストをクリア
        searchText = ""
        suggestions = []
        
        // タグを一度に追加（Combineのバインディングが1回だけ実行される）
        if !tagsToAdd.isEmpty {
            selectedTags.append(contentsOf: tagsToAdd)
        }
    }
    
    // MARK: - Tag Helper Methods
    
    /// タグIDから表示名を取得
    func getTagDisplayName(for tagId: String) -> String {
        allTags.first { $0.id == tagId }?.displayName ?? tagId
    }
    
    /// 複数のタグIDからTag配列を取得
    func getTagsForIds(_ tagIds: [String]) -> [Tag] {
        tagIds.compactMap { tagId in
            allTags.first { $0.id == tagId }
        }
    }
    
    // MARK: - Tag Selection Methods
    
    func selectTag(_ tag: Tag) {
        // オートコンプリート：選択されたタグ名をテキストフィールドに設定
        searchText = tag.displayName
        
        // 候補を非表示
        suggestions = []
    }
    
    func addSelectedTagFromSuggestion(_ tag: Tag) {
        // 重複チェック
        guard !selectedTags.contains(where: { $0.id == tag.id }) else { return }
        
        // タグを選択リストに直接追加
        selectedTags.append(tag)
        
        // テキストと候補をクリア
        searchText = ""
        suggestions = []
    }
    
    func addSelectedTag() {
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 正規化して一致するタグを探す
        guard let matchingTag = allTags.first(where: { tag in
            let normalizedDisplayName = tagSuggestionService.normalizeJapaneseText(tag.displayName)
            let normalizedQuery = tagSuggestionService.normalizeJapaneseText(trimmedText)
            return normalizedDisplayName.lowercased() == normalizedQuery.lowercased()
        }) else { return }
        
        // 重複チェック
        guard !selectedTags.contains(where: { $0.id == matchingTag.id }) else { return }
        
        // タグを選択リストに追加
        selectedTags.append(matchingTag)
        
        // テキストをクリア
        searchText = ""
        suggestions = []
    }
    
    func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0.id == tag.id }
    }
    
    func clearAllTags() {
        selectedTags.removeAll()
        state = .initial
        currentCreators = []
        hasMore = false
        currentOffset = 0
        totalCount = 0
    }
    
    func deleteFromHistory(_ query: String) async {
        do {
            try await saveSearchHistoryUseCase.execute(query: query)
            loadSearchHistory()
        } catch {
        }
    }
    
    func clearHistory() async {
        do {
            try await clearSearchHistoryUseCase.execute()
            loadSearchHistory()
        } catch {
        }
    }
    
    func searchWithTag(_ tag: Tag) {
        if allTags.isEmpty {
            Task {
                await loadAllTagsAsync()
                await MainActor.run {
                    self.searchWithTag(tag)
                }
            }
            return
        }
        
        // 既存のタグをクリアして新しいタグを設定
        selectedTags.append(tag)
        searchText = ""
        suggestions = []
    }
}
