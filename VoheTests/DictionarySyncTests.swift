import XCTest
import SwiftData
@testable import Vohe

@MainActor
final class DictionarySyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    /// (deckName, oldFront, oldBack, newFront, newBack) for every stats migration.
    private var renames: [[String]] = []

    override func setUp() async throws {
        let schema = Schema([Deck.self, Card.self, SessionResult.self, PausedSession.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        renames = []
    }

    private func recordRename(
        _ deckName: String,
        _ oldFront: String, _ oldBack: String,
        _ newFront: String, _ newBack: String
    ) {
        renames.append([deckName, oldFront, oldBack, newFront, newBack])
    }

    private func makeDeck(name: String = "Croatian-Italian") -> Deck {
        let deck = Deck(name: name, language1: "Croatian", language2: "Italian")
        context.insert(deck)
        return deck
    }

    @discardableResult
    private func insertCard(_ deck: Deck, _ front: String, _ back: String) -> Card {
        let card = Card(front: front, back: back)
        card.deck = deck
        context.insert(card)
        return card
    }

    private func remote(
        id: Int = 7,
        version: Int = 3,
        _ pairs: [(String, String)]
    ) -> RemoteDictionary {
        RemoteDictionary(
            id: id,
            name: "Croatian-Italian",
            language1: "Croatian",
            language2: "Italian",
            version: version,
            entries: pairs.map { RemoteWord(word: $0.0, translation: $0.1) }
        )
    }

    private func apply(_ dictionary: RemoteDictionary, to deck: Deck) -> DictionarySync.MergeReport {
        DictionarySync.apply(dictionary, to: deck, context: context, renameStats: recordRename)
    }

    private func card(_ deck: Deck, _ front: String) -> Card? {
        deck.cards.first { $0.front == front }
    }

    // MARK: - Acceptance 4 & 5: linking and version tracking

    func testFirstPullAddsEveryWordAndLinksTheDeck() {
        let deck = makeDeck()
        let report = apply(remote(version: 4, [("pas", "cane"), ("mačka", "gatto")]), to: deck)

        XCTAssertEqual(deck.cards.count, 2)
        XCTAssertEqual(deck.remoteID, 7)
        XCTAssertEqual(deck.syncedVersion, 4)
        XCTAssertFalse(deck.updateAvailable)
        XCTAssertEqual(report, DictionarySync.MergeReport(added: 2, updated: 0, approved: 0, localOnly: 0))
        // New words start as unseen cards, like any freshly imported deck.
        XCTAssertEqual(card(deck, "pas")?.boxIndex, 0)
        XCTAssertEqual(card(deck, "pas")?.remoteBack, "cane")
        XCTAssertFalse(card(deck, "pas")?.isLocalOnly ?? true)
    }

    func testCatalogVersionRaisesTheBadgeWithoutTouchingWords() {
        let deck = makeDeck()
        apply(remote(version: 4, [("pas", "cane")]), to: deck)

        DictionarySync.noteCatalogVersions(
            [RemoteDictionarySummary(
                id: 7, name: "Croatian-Italian", language1: "Croatian",
                language2: "Italian", version: 6, wordCount: 12
            )],
            in: [deck]
        )

        XCTAssertTrue(deck.updateAvailable)
        XCTAssertEqual(deck.syncedVersion, 4, "the badge must not pretend the words were pulled")
        XCTAssertEqual(deck.cards.count, 1)
    }

    func testUnknownAndUnlinkedDecksIgnoreTheCatalog() {
        let unlinked = makeDeck(name: "Only local")
        DictionarySync.noteCatalogVersions(
            [RemoteDictionarySummary(
                id: 7, name: "Croatian-Italian", language1: "Croatian",
                language2: "Italian", version: 9, wordCount: 1
            )],
            in: [unlinked]
        )
        XCTAssertEqual(unlinked.latestRemoteVersion, 0)
        XCTAssertFalse(unlinked.updateAvailable)
    }

    func testAnExistingTextImportIsAdoptedInsteadOfDuplicated() {
        let fromFile = makeDeck(name: "Croatian-Italian")
        let linkedElsewhere = makeDeck(name: "Other")
        linkedElsewhere.remoteID = 7

        let summary = RemoteDictionarySummary(
            id: 7, name: "Croatian-Italian", language1: "Croatian",
            language2: "Italian", version: 1, wordCount: 1
        )
        // An already-linked deck wins over a name match.
        XCTAssertIdentical(
            DictionarySync.existingDeck(for: summary, in: [fromFile, linkedElsewhere]),
            linkedElsewhere
        )
        XCTAssertIdentical(
            DictionarySync.existingDeck(for: summary, in: [fromFile]),
            fromFile
        )
        // A deck linked to a different dictionary is never adopted by name.
        fromFile.remoteID = 99
        XCTAssertNil(DictionarySync.existingDeck(for: summary, in: [fromFile]))
    }

    // MARK: - Acceptance 6 & 7: nothing lost, history preserved

    func testUpdateKeepsLeitnerStateOfUnchangedWords() {
        let deck = makeDeck()
        let pas = insertCard(deck, "pas", "cane")
        pas.boxIndex = 4
        pas.nextDue = Date(timeIntervalSince1970: 1_800_000_000)
        pas.wrongLastSession = true

        apply(remote([("pas", "cane"), ("mačka", "gatto")]), to: deck)

        XCTAssertEqual(pas.boxIndex, 4)
        XCTAssertEqual(pas.nextDue, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(pas.wrongLastSession)
        XCTAssertEqual(deck.cards.count, 2)
        XCTAssertTrue(renames.isEmpty)
    }

    func testAnApprovedRetranslationCarriesTheCardsStatsOver() {
        let deck = makeDeck()
        let pas = insertCard(deck, "pas", "cane")
        pas.boxIndex = 3
        pas.needsValidation = true

        let report = apply(remote([("pas", "il cane")]), to: deck)

        XCTAssertEqual(pas.back, "il cane")
        XCTAssertEqual(pas.boxIndex, 3, "a re-translation is not a scheduling event")
        XCTAssertFalse(pas.needsValidation, "an approved word needs no on-device validation")
        XCTAssertEqual(renames, [["Croatian-Italian", "pas", "cane", "pas", "il cane"]])
        XCTAssertEqual(report.updated, 1)
    }

    func testWordsDroppedFromTheDictionaryStayAndAreMarkedLocalOnly() {
        let deck = makeDeck()
        let pas = insertCard(deck, "pas", "cane")
        let mine = insertCard(deck, "kuća", "casa")
        apply(remote(version: 1, [("pas", "cane"), ("kuća", "casa")]), to: deck)
        XCTAssertFalse(mine.isLocalOnly)

        // The next version no longer carries "kuća".
        let report = apply(remote(version: 2, [("pas", "cane")]), to: deck)

        XCTAssertEqual(deck.cards.count, 2, "an update must never delete a card")
        XCTAssertEqual(mine.back, "casa")
        XCTAssertFalse(pas.isLocalOnly)
        // It keeps the text it had; it is simply no longer part of the
        // dictionary, which the app shows as "only on this iPhone".
        XCTAssertTrue(mine.isLocalOnly)
        XCTAssertTrue(mine.needsSubmission)
        XCTAssertEqual(report.localOnly, 1)
        XCTAssertEqual(deck.syncedVersion, 2)
    }

    func testAWordAddedOnThisDeviceIsLocalOnlyAndAwaitsSubmission() {
        let deck = makeDeck()
        apply(remote([("pas", "cane")]), to: deck)
        let mine = insertCard(deck, "kuća", "casa")

        XCTAssertTrue(mine.isLocalOnly)
        XCTAssertTrue(mine.needsSubmission)
        XCTAssertEqual(DictionarySync.cardsNeedingSubmission(in: deck).map(\.front), ["kuća"])
        XCTAssertEqual(DictionarySync.cardsAwaitingReview(in: deck).count, 0)
    }

    // MARK: - Acceptance 2: review before it becomes shared

    func testAWordWaitingForReviewSurvivesAnUpdate() {
        let deck = makeDeck()
        apply(remote(version: 1, [("pas", "cane")]), to: deck)
        let pas = card(deck, "pas")!
        pas.back = "il cane" // edited here
        DictionarySync.markSubmitted([pas])

        // Someone else publishes an unrelated word; "pas" is untouched upstream.
        let report = apply(remote(version: 2, [("pas", "cane"), ("mačka", "gatto")]), to: deck)

        XCTAssertEqual(pas.back, "il cane", "the edit under review must not be overwritten")
        XCTAssertTrue(pas.pendingReview)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.added, 1)
        XCTAssertTrue(renames.isEmpty)
    }

    func testApprovalClearsTheWaitingMarkWithoutRewritingTheCard() {
        let deck = makeDeck()
        apply(remote(version: 1, [("pas", "cane")]), to: deck)
        let pas = card(deck, "pas")!
        pas.back = "il cane"
        pas.boxIndex = 2
        DictionarySync.markSubmitted([pas])

        let report = apply(remote(version: 2, [("pas", "il cane")]), to: deck)

        XCTAssertFalse(pas.pendingReview)
        XCTAssertFalse(pas.needsSubmission)
        XCTAssertEqual(pas.back, "il cane")
        XCTAssertEqual(pas.boxIndex, 2)
        XCTAssertEqual(report.approved, 1)
        XCTAssertEqual(report.updated, 0)
        XCTAssertTrue(renames.isEmpty, "the text didn't change, so stats stay put")
    }

    func testAReviewerEditingTheProposalWins() {
        let deck = makeDeck()
        apply(remote(version: 1, [("pas", "cane")]), to: deck)
        let pas = card(deck, "pas")!
        pas.back = "il cane"
        DictionarySync.markSubmitted([pas])

        // Approved, but the reviewer settled on a different wording.
        apply(remote(version: 2, [("pas", "cane, il cane")]), to: deck)

        XCTAssertEqual(pas.back, "cane, il cane")
        XCTAssertFalse(pas.pendingReview)
        XCTAssertFalse(pas.needsSubmission)
        XCTAssertEqual(renames, [["Croatian-Italian", "pas", "il cane", "pas", "cane, il cane"]])
    }

    func testANewWordApprovedUpstreamStopsBeingLocalOnly() {
        let deck = makeDeck()
        apply(remote(version: 1, [("pas", "cane")]), to: deck)
        let mine = insertCard(deck, "kuća", "casa")
        DictionarySync.markSubmitted([mine])

        let report = apply(remote(version: 2, [("pas", "cane"), ("kuća", "casa")]), to: deck)

        XCTAssertFalse(mine.isLocalOnly)
        XCTAssertFalse(mine.pendingReview)
        XCTAssertEqual(deck.cards.count, 2, "the approved word must not be duplicated")
        XCTAssertEqual(report.added, 0)
        XCTAssertEqual(report.approved, 1)
    }

    func testAnUnsubmittedLocalEditIsReplacedByTheDictionary() {
        let deck = makeDeck()
        apply(remote(version: 1, [("pas", "cane")]), to: deck)
        let pas = card(deck, "pas")!
        pas.back = "il cane" // changed here, never sent for review

        let report = apply(remote(version: 2, [("pas", "cane")]), to: deck)

        XCTAssertEqual(pas.back, "cane", "the dictionary is authoritative for words nobody is reviewing")
        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(renames, [["Croatian-Italian", "pas", "il cane", "pas", "cane"]])
    }
}
